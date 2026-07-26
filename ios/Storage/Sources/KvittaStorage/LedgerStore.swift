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

    private let store: EventStore
    private let authorId: UserID
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

    /// Folds the whole log into a fresh projection.
    ///
    /// This is both what launch does and what the debug menu's "rebuild projections" does — the
    /// same function, so the recovery path cannot quietly rot while nobody is looking at it.
    public func rebuild() throws {
        let loaded = try store.allEvents()
        state = Projector.replay(loaded.events)
        rejected = loaded.rejected
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
}
