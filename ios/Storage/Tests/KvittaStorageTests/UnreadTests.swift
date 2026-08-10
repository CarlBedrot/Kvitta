import Foundation
import Testing
import KvittaCore
import KvittaCoreTestSupport
@testable import KvittaStorage

/// What counts as unread, and — more importantly — what does not.
///
/// Read state is device-local and never an event: an "I have seen this" event would be copied to
/// every member's phone forever with no way to take it back, and whether you have read something
/// is not the group's business. So the whole mechanism is one integer per device, plus these rules.
@Suite("Unread")
@MainActor
struct UnreadTests {
    private static let otherUser = UserID(uuidString: "00000000-0000-0000-000b-000000000002")!

    /// `receivedAt` is stamped from the store's clock, so testing anything about arrival order
    /// needs a clock that moves. `EventStore` wants a `@Sendable` closure, hence a class rather
    /// than a captured `var`.
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Timestamp

        init(_ start: Timestamp = Fixtures.timestamp) { value = start }

        var now: Timestamp {
            lock.lock(); defer { lock.unlock() }
            return value
        }

        /// A second later. The unit does not matter; only that arrivals are ordered.
        func tick() {
            lock.lock(); defer { lock.unlock() }
            value = Timestamp(epochMilliseconds: value.epochMilliseconds + 1_000)
        }
    }

    private func makeLedger(_ clock: Clock) throws -> LedgerStore {
        LedgerStore(
            store: try EventStore.inMemory(now: { clock.now }),
            authorId: Fixtures.authorId,
            now: { clock.now }
        )
    }

    @Test("Somebody else's event that arrived after the mark is unread")
    func othersEventIsUnread() throws {
        let clock = Clock()
        let ledger = try makeLedger(clock)
        var factory = EventFactory()

        let mark = try ledger.latestReceivedAt()
        clock.tick()
        let expense = Fixtures.expense(1)
        try ledger.integrate([factory.make(
            entityId: expense.rawValue,
            payload: .expenseDeleted(EmptyPayload()),
            author: Self.otherUser
        )])

        #expect(try ledger.unreadEntities(since: mark) == [expense.rawValue])
    }

    /// Your own expense reaches your own log the instant you tap save. Without this rule the app
    /// would notify you about yourself on every entry you make, which is the fastest possible way
    /// to teach someone that the badge means nothing.
    @Test("Your own event is never unread")
    func ownEventIsNotUnread() throws {
        let clock = Clock()
        let ledger = try makeLedger(clock)
        var factory = EventFactory()

        let mark = try ledger.latestReceivedAt()
        clock.tick()
        try ledger.integrate([factory.make(
            entityId: Fixtures.expense(1).rawValue,
            payload: .expenseDeleted(EmptyPayload()),
            author: Fixtures.authorId
        )])

        #expect(try ledger.unreadEntities(since: mark).isEmpty)
    }

    @Test("Nothing is unread once the mark has caught up")
    func markCatchesUp() throws {
        let clock = Clock()
        let ledger = try makeLedger(clock)
        var factory = EventFactory()

        clock.tick()
        try ledger.integrate([factory.make(
            entityId: Fixtures.expense(1).rawValue,
            payload: .expenseDeleted(EmptyPayload()),
            author: Self.otherUser
        )])

        let mark = try ledger.latestReceivedAt()
        #expect(try ledger.unreadEntities(since: mark).isEmpty)
    }

    /// The bug the whole design exists to avoid.
    ///
    /// `EventFactory` stamps `clientTimestamp` from a fixed 2026-05 base, far in the past relative
    /// to the clock this store runs on — so if unread were decided by the event's own timestamp,
    /// this event would arrive already older than the mark and be marked read without ever having
    /// been drawn. `receivedAt` cannot go backwards for this device, which is the only property
    /// the mark needs.
    @Test("An event whose own timestamp predates the mark is still unread if it just arrived")
    func lateArrivalWithOldTimestampIsUnread() throws {
        let clock = Clock(Timestamp(iso8601: "2026-08-10T20:00:00Z")!)
        let ledger = try makeLedger(clock)
        var factory = EventFactory()

        let mark = try ledger.latestReceivedAt()
        clock.tick()
        let expense = Fixtures.expense(1)
        let stale = factory.make(
            entityId: expense.rawValue,
            payload: .expenseDeleted(EmptyPayload()),
            author: Self.otherUser
        )
        #expect(stale.clientTimestamp < Timestamp(iso8601: "2026-08-10T20:00:00Z")!)
        try ledger.integrate([stale])

        #expect(try ledger.unreadEntities(since: mark) == [expense.rawValue])
    }

    /// The feed shows one row per expense, not one per event. Three edits are one thing to read.
    @Test("Several events about one entity count as one unread row")
    func editsCollapseToOneEntity() throws {
        let clock = Clock()
        let ledger = try makeLedger(clock)
        var factory = EventFactory()
        let expense = Fixtures.expense(1)

        let mark = try ledger.latestReceivedAt()
        for _ in 0..<3 {
            clock.tick()
            try ledger.integrate([factory.make(
                entityId: expense.rawValue,
                payload: .expenseDeleted(EmptyPayload()),
                author: Self.otherUser
            )])
        }

        #expect(try ledger.unreadEntities(since: mark) == [expense.rawValue])
    }

    /// Two people acting between two visits are two rows, not one lump.
    @Test("Different entities count separately")
    func differentEntitiesCountSeparately() throws {
        let clock = Clock()
        let ledger = try makeLedger(clock)
        var factory = EventFactory()

        let mark = try ledger.latestReceivedAt()
        clock.tick()
        try ledger.integrate([
            factory.make(
                entityId: Fixtures.expense(1).rawValue,
                payload: .expenseDeleted(EmptyPayload()),
                author: Self.otherUser
            ),
            factory.make(
                entityId: Fixtures.expense(2).rawValue,
                payload: .expenseDeleted(EmptyPayload()),
                author: Self.otherUser
            )
        ])

        #expect(try ledger.unreadEntities(since: mark).count == 2)
    }

    /// A fresh install must not open on a badge counting a history it has never had.
    @Test("An empty log has nothing unread and a zero mark")
    func emptyLog() throws {
        let ledger = try makeLedger(Clock())

        #expect(try ledger.latestReceivedAt() == 0)
        #expect(try ledger.unreadEntities(since: 0).isEmpty)
    }
}
