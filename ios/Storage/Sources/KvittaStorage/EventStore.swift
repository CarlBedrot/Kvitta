import Foundation
import GRDB
import KvittaCore

/// Where an event came from, which decides whether it needs pushing.
public enum EventOrigin: Sendable {
    /// Created on this device. Goes into the outbox as well as the log.
    case local
    /// Pulled from the server, so already ordered and already everyone else's problem.
    case remote
}

/// An event the server refused on its merits, kept so it can be shown rather than dropped (§7).
public struct RejectedPush: Hashable, Sendable {
    public let event: EventEnvelope
    /// The server's stable rejection code, e.g. `money_invariant_violated`.
    public let code: String
    public let rejectedAt: Timestamp

    public init(event: EventEnvelope, code: String, rejectedAt: Timestamp) {
        self.event = event
        self.code = code
        self.rejectedAt = rejectedAt
    }
}

/// Events loaded from disk, plus anything that could not be read.
public struct LoadResult: Sendable {
    public let events: [EventEnvelope]
    /// Rows that would not decode. Surfaced rather than thrown, on the same reasoning as
    /// `EventCoding.decodeBatch`: one unreadable row must not cost the user their history.
    public let rejected: [RejectedEvent]

    public init(events: [EventEnvelope], rejected: [RejectedEvent]) {
        self.events = events
        self.rejected = rejected
    }
}

/// The event log on disk, plus the outbox and pull cursors that sync will need.
///
/// This type knows nothing about balances. It stores events and hands them back in replay order;
/// `Projector` decides what they mean.
public struct EventStore: Sendable {
    private let writer: any DatabaseWriter
    private let now: @Sendable () -> Timestamp

    public init(
        _ writer: any DatabaseWriter,
        now: @escaping @Sendable () -> Timestamp = { Timestamp(Date()) }
    ) throws {
        self.writer = writer
        self.now = now
        try Schema.migrator.migrate(writer)
    }

    /// A throwaway database. Tests run against this, so the whole suite needs no simulator.
    public static func inMemory(
        now: @escaping @Sendable () -> Timestamp = { Timestamp(Date()) }
    ) throws -> EventStore {
        try EventStore(try DatabaseQueue(), now: now)
    }

    public static func onDisk(at url: URL) throws -> EventStore {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try EventStore(try DatabaseQueue(path: url.path))
    }

    // MARK: - Writing

    /// Appends events, ignoring any whose `eventId` is already present.
    ///
    /// The duplicate-tolerance is not politeness, it is the design: push-then-pull-back returns
    /// your own events to you, and overlapping sync pages re-deliver their neighbours. Both are
    /// no-ops here, exactly as they are in `Projector`.
    public func append(_ events: [EventEnvelope], origin: EventOrigin) throws {
        guard !events.isEmpty else { return }
        let queuedAt = now().epochMilliseconds

        try writer.write { db in
            for event in events {
                let payload = try EventCoding.encode(event)
                try db.execute(
                    sql: """
                        INSERT INTO event
                            (eventId, groupId, serverSeq, clientTimestamp, receivedAt, payload)
                        VALUES (?, ?, ?, ?, ?, ?)
                        ON CONFLICT(eventId) DO NOTHING
                        """,
                    arguments: [
                        event.eventId.rawValue.uuidString,
                        event.groupId.rawValue.uuidString,
                        event.serverSeq,
                        event.clientTimestamp.epochMilliseconds,
                        queuedAt,
                        payload
                    ]
                )

                if origin == .local {
                    try db.execute(
                        sql: """
                            INSERT INTO outbox (eventId, queuedAt) VALUES (?, ?)
                            ON CONFLICT(eventId) DO NOTHING
                            """,
                        arguments: [event.eventId.rawValue.uuidString, queuedAt]
                    )
                }
            }
        }
    }

    /// Records the sequence numbers the server assigned and clears those events from the outbox.
    ///
    /// One transaction, because an event that is stamped but still queued would be pushed twice,
    /// and one that is dequeued but unstamped would replay in the wrong place forever.
    public func acknowledge(_ acknowledgements: [(eventId: EventID, serverSeq: Int64)]) throws {
        guard !acknowledgements.isEmpty else { return }
        try writer.write { db in
            for ack in acknowledgements {
                let id = ack.eventId.rawValue.uuidString
                try db.execute(
                    sql: "UPDATE event SET serverSeq = ? WHERE eventId = ?",
                    arguments: [ack.serverSeq, id]
                )
                try db.execute(sql: "DELETE FROM outbox WHERE eventId = ?", arguments: [id])
            }
        }
    }

    /// Notes a failed push attempt. The events stay queued — CLAUDE.md forbids dropping them
    /// silently, so the count and the message are kept for the sync status screen.
    public func recordPushFailure(_ eventIds: [EventID], error: String) throws {
        guard !eventIds.isEmpty else { return }
        try writer.write { db in
            for eventId in eventIds {
                try db.execute(
                    sql: """
                        UPDATE outbox SET attemptCount = attemptCount + 1, lastError = ?
                        WHERE eventId = ?
                        """,
                    arguments: [error, eventId.rawValue.uuidString]
                )
            }
        }
    }

    /// Marks events the server refused on their merits.
    ///
    /// They leave the retry queue but stay in the database and stay visible, because the log is
    /// still the only record that the user ever entered them. The event row itself is untouched —
    /// it remains in the local log and keeps contributing to local balances, which is correct:
    /// the expense really did happen, it just is not agreed with anyone else yet.
    public func markRejected(_ rejections: [(eventId: EventID, code: String)]) throws {
        guard !rejections.isEmpty else { return }
        let rejectedAt = now().epochMilliseconds

        try writer.write { db in
            for rejection in rejections {
                try db.execute(
                    sql: """
                        UPDATE outbox SET rejectedAt = ?, rejectionCode = ?
                        WHERE eventId = ?
                        """,
                    arguments: [rejectedAt, rejection.code, rejection.eventId.rawValue.uuidString]
                )
            }
        }
    }

    // MARK: - Reading

    public func allEvents() throws -> LoadResult {
        try load(sql: Self.replayOrderSQL, arguments: [])
    }

    public func events(inGroup groupId: GroupID) throws -> LoadResult {
        try load(
            sql: "\(Self.selectAll) WHERE groupId = ? \(Self.replayOrderClause)",
            arguments: [groupId.rawValue.uuidString]
        )
    }

    /// The oldest events still waiting to be pushed, in the order they were created.
    ///
    /// Rejected events are excluded: retrying something the server has already refused on its
    /// merits would spin forever and, worse, would keep the good events behind it from draining.
    public func outboxBatch(limit: Int = 500) throws -> LoadResult {
        try load(
            sql: """
                SELECT event.payload, event.serverSeq FROM event
                JOIN outbox ON outbox.eventId = event.eventId
                WHERE outbox.rejectedAt IS NULL
                ORDER BY outbox.queuedAt, event.rowid
                LIMIT ?
                """,
            arguments: [limit]
        )
    }

    /// How many events are still retryable. Rejected ones are counted by `rejectedPushes`.
    public func outboxCount() throws -> Int {
        try writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM outbox WHERE rejectedAt IS NULL") ?? 0
        }
    }

    /// Events the server refused, newest first — what the sync-status screen shows.
    public func rejectedPushes() throws -> [RejectedPush] {
        let rows = try writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT event.payload, event.serverSeq, outbox.rejectionCode, outbox.rejectedAt
                    FROM event
                    JOIN outbox ON outbox.eventId = event.eventId
                    WHERE outbox.rejectedAt IS NOT NULL
                    ORDER BY outbox.rejectedAt DESC, event.rowid DESC
                    """
            ).map { row in
                (
                    payload: row["payload"] as Data,
                    serverSeq: row["serverSeq"] as Int64?,
                    code: (row["rejectionCode"] as String?) ?? "",
                    rejectedAt: (row["rejectedAt"] as Int64?) ?? 0
                )
            }
        }

        return rows.compactMap { row in
            guard let event = try? EventCoding.decode(row.payload).withServerSeq(row.serverSeq) else {
                return nil
            }
            return RejectedPush(
                event: event,
                code: row.code,
                rejectedAt: Timestamp(epochMilliseconds: row.rejectedAt)
            )
        }
    }

    /// The entities this device first heard about after `mark`, ignoring anything `author` wrote.
    ///
    /// The filter is on `receivedAt` — when this phone learned the event existed — and deliberately
    /// not on `clientTimestamp`. An expense someone entered on Friday can reach you on Sunday, and
    /// against a clock it would arrive already older than the last time you looked, so it would be
    /// silently marked as read having never been on screen. `receivedAt` cannot go backwards for
    /// this device, which is the only property the unread mark actually needs.
    ///
    /// Excluding your own authorship is not cosmetic either: your own expense reaches your own
    /// outbox the instant you tap save, so without this every entry you make would notify you
    /// about yourself.
    ///
    /// Entity rather than event ids, because that is what the feed shows: editing an expense three
    /// times is three events and one row, and that row is unread once, not three times.
    ///
    /// Only rows past the mark are decoded, so the cost is bounded by what is new rather than by
    /// the size of the log.
    public func entitiesReceived(after mark: Int64, excludingAuthor author: UserID) throws -> Set<UUID> {
        let payloads = try writer.read { db in
            try Data.fetchAll(
                db,
                sql: "SELECT payload FROM event WHERE receivedAt > ?",
                arguments: [mark]
            )
        }

        var entities: Set<UUID> = []
        for payload in payloads {
            // An unreadable row costs its badge, never the screen — same reasoning as `load`.
            guard let event = try? EventCoding.decode(payload), event.authorId != author else {
                continue
            }
            entities.insert(event.entityId)
        }
        return entities
    }

    /// The high-water mark to store when the user has seen everything currently known.
    ///
    /// Read before showing the feed rather than stamping "now" after it: an event that lands while
    /// the screen is open would otherwise be marked read without ever having been drawn.
    public func latestReceivedAt() throws -> Int64 {
        try writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT MAX(receivedAt) FROM event") ?? 0
        }
    }

    public func eventCount() throws -> Int {
        try writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM event") ?? 0
        }
    }

    // MARK: - Cursors

    public func cursor(forGroup groupId: GroupID) throws -> Int64 {
        try writer.read { db in
            try Int64.fetchOne(
                db,
                sql: "SELECT lastServerSeq FROM groupCursor WHERE groupId = ?",
                arguments: [groupId.rawValue.uuidString]
            ) ?? 0
        }
    }

    public func setCursor(_ serverSeq: Int64, forGroup groupId: GroupID) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO groupCursor (groupId, lastServerSeq) VALUES (?, ?)
                    ON CONFLICT(groupId) DO UPDATE SET lastServerSeq = MAX(lastServerSeq, excluded.lastServerSeq)
                    """,
                arguments: [groupId.rawValue.uuidString, serverSeq]
            )
        }
    }

    // MARK: - Internals

    private static let selectAll = "SELECT payload, serverSeq FROM event"

    /// Acknowledged events in server order, then pending ones by insertion — design doc §6's
    /// ordering rule, expressed as an ORDER BY so the database does the sorting.
    private static let replayOrderClause = "ORDER BY serverSeq IS NULL, serverSeq, rowid"

    private static let replayOrderSQL = "\(selectAll) \(replayOrderClause)"

    private func load(sql: String, arguments: StatementArguments) throws -> LoadResult {
        let rows: [(payload: Data, serverSeq: Int64?)] = try writer.read { db in
            try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
                (payload: row["payload"] as Data, serverSeq: row["serverSeq"] as Int64?)
            }
        }

        var events: [EventEnvelope] = []
        var rejected: [RejectedEvent] = []
        events.reserveCapacity(rows.count)

        for (index, row) in rows.enumerated() {
            let payload = row.payload
            do {
                // The column wins over the copy inside the payload. An acknowledgement updates
                // the column only — rewriting the stored bytes on every ack would churn the log
                // for a fact the column already holds, and the bytes are meant to stay as they
                // arrived.
                events.append(try EventCoding.decode(payload).withServerSeq(row.serverSeq))
            } catch {
                rejected.append(
                    RejectedEvent(
                        index: index,
                        eventId: nil,
                        reason: String(describing: error),
                        raw: (try? EventCoding.makeDecoder().decode(JSONValue.self, from: payload))
                            ?? .null
                    )
                )
            }
        }

        return LoadResult(events: events, rejected: rejected)
    }
}
