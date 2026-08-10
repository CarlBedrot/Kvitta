import Foundation
import KvittaCore

/// The app's view of the ledger, and the only way to change it.
///
/// The whole point of this type is that **writing an event and updating the projection are one
/// call**. There is no API to append to the log without folding the result into `state`, and none
/// to touch `state` without writing to the log. The classic event-sourcing bug — a balance on
/// screen that disagrees with the log behind it — is not something the caller can express.
///
/// Projections live here in memory rather than in the database. A heavy group replays in about
/// 20 ms (`ReplayPerformanceTests`), so caching them would buy nothing and cost a second copy of
/// the truth that could drift from the first. It also means `rebuild()` and launch are the same
/// code path, so the recovery hatch is exercised every time the app opens instead of never.
@MainActor
@Observable
public final class LedgerStore {
    public private(set) var state: LedgerState = .empty
    /// Rows that would not decode on the last load. Not fatal, but not hidden either.
    public private(set) var rejected: [RejectedEvent] = []

    /// Events the server refused. They stay in the local log and still count toward local
    /// balances — the expense really happened, it just is not agreed with anyone else yet — but
    /// they no longer retry, and the UI can show which ones and why.
    public private(set) var rejectedPushes: [RejectedPush] = []

    /// Called after a local event has been written and applied.
    ///
    /// Exists so that "a local mutation happened" has exactly one place to be noticed. The app
    /// wires this to the sync engine's debounced push (`Bootstrap`), which is the only reason it
    /// exists — but the hook is deliberately untyped and Storage stays ignorant of Sync.
    ///
    /// The alternative, calling the sync engine from each save site, is what this replaces: there
    /// are six or seven of them (new expense, settle-up, new group, members, edit, delete) and
    /// the first version of this app shipped with *none* of them calling it. Saving an expense
    /// left it in the outbox until the app happened to be foregrounded again, which looks exactly
    /// like sync being unreliable. One hook at the single documented write path cannot be
    /// forgotten by a new call site, because new call sites go through `record` too.
    ///
    /// Not fired by `integrate`: those events came *from* the server and pushing them back would
    /// be a loop.
    public var onRecord: (@MainActor () -> Void)?

    private let store: EventStore
    private var authorId: UserID
    private let now: @Sendable () -> Timestamp

    public init(
        store: EventStore,
        authorId: UserID,
        now: @escaping @Sendable () -> Timestamp = { Timestamp(Date()) }
    ) {
        self.store = store
        self.authorId = authorId
        self.now = now
    }

    /// Who new events are authored by, from here on.
    ///
    /// A `var` rather than a `let` for a specific reason: signing in changes the user's identity,
    /// and the alternative — rebuilding the whole `LedgerStore` — would open a second GRDB
    /// `DatabaseQueue` on the same file while the old store is still retained by SwiftUI state.
    /// GRDB serialises writes within a queue, not across two of them, so that is a route straight
    /// to `SQLITE_BUSY`.
    ///
    /// Nothing already written is touched. Events are immutable, so historical `authorId` values
    /// keep pointing at whoever wrote them — which is correct, and is also why a group created
    /// before signing in cannot simply be adopted afterwards.
    public func setAuthor(_ userId: UserID) {
        authorId = userId
    }

    /// The identity new events will carry.
    public var currentAuthorId: UserID { authorId }

    /// Folds the whole log into a fresh projection.
    ///
    /// This is both what launch does and what the debug menu's "rebuild projections" does — the
    /// same function, so the recovery path cannot quietly rot while nobody is looking at it.
    public func rebuild() throws {
        let loaded = try store.allEvents()
        state = Projector.replay(loaded.events)
        rejected = loaded.rejected
        rejectedPushes = (try? store.rejectedPushes()) ?? []
    }

    /// Writes a new local event and applies it, in that order.
    ///
    /// Order matters: if the append throws, `state` is untouched and the user sees the failure
    /// rather than an expense that looks saved and is not.
    @discardableResult
    public func record(
        _ payload: EventPayload,
        entityId: UUID,
        in groupId: GroupID
    ) throws -> EventEnvelope {
        let event = EventEnvelope(
            groupId: groupId,
            entityId: entityId,
            authorId: authorId,
            clientTimestamp: now(),
            serverSeq: nil, // local until the server says otherwise
            payload: payload
        )
        try store.append([event], origin: .local)
        state = Projector.apply(state, event)
        // After the write has succeeded, so a failed append never schedules a push for an event
        // that does not exist.
        onRecord?()
        return event
    }

    /// Applies events pulled from the server.
    ///
    /// Rebuilds rather than folding onto the current state, because pulled events can interleave
    /// *before* unacknowledged local ones and the projection has to end up in `serverSeq` order
    /// (design doc §6). At 20 ms a rebuild, a cleverer patching scheme would be all risk and no
    /// reward.
    public func integrate(_ events: [EventEnvelope]) throws {
        guard !events.isEmpty else { return }
        try store.append(events, origin: .remote)
        try rebuild()
    }

    // MARK: - Sync bookkeeping, for Session 3

    public func pendingPushCount() throws -> Int {
        try store.outboxCount()
    }

    public func outboxBatch(limit: Int = 500) throws -> [EventEnvelope] {
        try store.outboxBatch(limit: limit).events
    }

    public func acknowledge(_ acknowledgements: [(eventId: EventID, serverSeq: Int64)]) throws {
        try store.acknowledge(acknowledgements)
        try rebuild()
    }

    /// Records that the server refused these events, so they stop retrying and start showing.
    public func markRejected(_ rejections: [(eventId: EventID, code: String)]) throws {
        try store.markRejected(rejections)
        rejectedPushes = try store.rejectedPushes()
    }

    /// Notes a transient push failure — offline, timeout, 500. The events stay queued.
    public func recordPushFailure(_ eventIds: [EventID], error: String) throws {
        try store.recordPushFailure(eventIds, error: error)
    }

    // MARK: - Unread

    /// Entities that arrived on this device after `mark` and were written by somebody else.
    ///
    /// The author to exclude is `currentAuthorId` rather than a parameter: "mine" can only mean
    /// this device's identity, and letting a caller pass a different one would let the feed claim
    /// somebody else's expenses were their own.
    public func unreadEntities(since mark: Int64) throws -> Set<UUID> {
        try store.entitiesReceived(after: mark, excludingAuthor: authorId)
    }

    /// The mark to save once the feed has been shown. See `EventStore.latestReceivedAt`.
    public func latestReceivedAt() throws -> Int64 {
        try store.latestReceivedAt()
    }

    // MARK: - Sync cursors

    public func cursor(forGroup groupId: GroupID) throws -> Int64 {
        try store.cursor(forGroup: groupId)
    }

    public func setCursor(_ serverSeq: Int64, forGroup groupId: GroupID) throws {
        try store.setCursor(serverSeq, forGroup: groupId)
    }
}
