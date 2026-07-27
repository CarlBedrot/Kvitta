import Foundation
import GRDB
import Testing
import KvittaCore
import KvittaCoreTestSupport
@testable import KvittaStorage

/// Migration v2: an event the server refuses on its merits has to leave the retry queue without
/// leaving the app. Retrying it forever would spin and would block everything behind it; dropping
/// it is forbidden outright (CLAUDE.md, design doc §7).
@Suite("Rejected pushes")
struct RejectedPushTests {

    private func storeWithTwoQueuedEvents() throws -> (EventStore, EventEnvelope, EventEnvelope) {
        let store = try EventStore.inMemory(now: { Fixtures.timestamp })
        var factory = EventFactory()
        let first = factory.groupCreated()
        let second = factory.memberAdded(Fixtures.member(1), name: "Carl")
        try store.append([first, second], origin: .local)
        return (store, first, second)
    }

    @Test("A rejected event stops being handed out for retry")
    func rejectedEventsLeaveTheRetryQueue() throws {
        let (store, first, second) = try storeWithTwoQueuedEvents()
        #expect(try store.outboxCount() == 2)

        try store.markRejected([(eventId: first.eventId, code: "money_invariant_violated")])

        #expect(try store.outboxCount() == 1)
        #expect(try store.outboxBatch().events == [second])
    }

    @Test("But it stays in the log, and stays visible with its reason")
    func rejectedEventsStayVisible() throws {
        let (store, first, _) = try storeWithTwoQueuedEvents()

        try store.markRejected([(eventId: first.eventId, code: "not_a_member")])

        let rejected = try store.rejectedPushes()
        #expect(rejected.count == 1)
        #expect(rejected.first?.event == first)
        #expect(rejected.first?.code == "not_a_member")

        // The event itself is untouched: the expense really happened locally, it simply is not
        // agreed with anyone else yet, so it must keep counting toward local balances.
        #expect(try store.eventCount() == 2)
        #expect(try store.allEvents().events.contains(first))
    }

    @Test("A transient failure is not a rejection — those events keep retrying")
    func transientFailuresStayQueued() throws {
        let (store, first, second) = try storeWithTwoQueuedEvents()

        try store.recordPushFailure([first.eventId, second.eventId], error: "offline")

        #expect(try store.outboxCount() == 2)
        #expect(try store.outboxBatch().events == [first, second])
        #expect(try store.rejectedPushes().isEmpty)
    }

    @Test("A database written before v2 migrates without losing its queue")
    func migratingAnExistingDatabaseKeepsTheOutbox() throws {
        let queue = try DatabaseQueue()

        // Stop at v1, which is exactly what an install from before this change has on disk.
        try Schema.migrator.migrate(queue, upTo: "v1")

        let before = try EventStore(queue, now: { Fixtures.timestamp })
        var factory = EventFactory()
        try before.append([factory.groupCreated()], origin: .local)
        #expect(try before.outboxCount() == 1)

        // Opening it again runs v2 on top.
        let after = try EventStore(queue, now: { Fixtures.timestamp })
        #expect(try after.outboxCount() == 1)
        #expect(try after.rejectedPushes().isEmpty)
    }

    @Test("LedgerStore surfaces rejections for the UI to badge")
    @MainActor
    func ledgerStoreExposesRejections() throws {
        let store = try EventStore.inMemory(now: { Fixtures.timestamp })
        let ledger = LedgerStore(store: store, authorId: Fixtures.authorId, now: { Fixtures.timestamp })

        let groupId = Fixtures.groupId
        let event = try ledger.record(
            .groupCreated(GroupCreatedPayload(name: "Fjällresan", currency: .sek)),
            entityId: groupId.rawValue,
            in: groupId
        )

        #expect(try ledger.pendingPushCount() == 1)
        #expect(ledger.rejectedPushes.isEmpty)

        try ledger.markRejected([(eventId: event.eventId, code: "money_invariant_violated")])

        #expect(try ledger.pendingPushCount() == 0)
        #expect(ledger.rejectedPushes.map(\.code) == ["money_invariant_violated"])
        // The group is still on screen. Rejection is a sync fact, not a data fact.
        #expect(ledger.state.groups[groupId] != nil)
    }
}
