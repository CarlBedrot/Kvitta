import Foundation
import GRDB
import Testing
import KvittaCore
import KvittaCoreTestSupport
@testable import KvittaStorage

@Suite("EventStore")
struct EventStoreTests {
    private let members = (1...3).map { Fixtures.member($0) }

    private func wineExpense() throws -> ExpensePayload {
        try ExpensePayload.make(
            description: "Systembolaget",
            categoryId: "alkohol",
            date: Fixtures.date,
            total: Money(amountMinor: 43_700, currency: .sek),
            paidBy: members[0],
            splitEquallyAmong: members
        )
    }

    private func openGroup() throws -> (EventFactory, [EventEnvelope]) {
        var factory = EventFactory()
        var events = [factory.groupCreated()]
        for (index, memberId) in members.enumerated() {
            events.append(factory.memberAdded(memberId, name: "Member \(index + 1)"))
        }
        events.append(factory.expenseCreated(Fixtures.expense(1), try wineExpense()))
        return (factory, events)
    }

    @Test("Events written come back out")
    func roundTrip() throws {
        let (_, events) = try openGroup()
        let store = try EventStore.inMemory()
        try store.append(events, origin: .remote)

        let loaded = try store.allEvents()
        #expect(loaded.rejected.isEmpty)
        #expect(loaded.events == events)
        #expect(try store.eventCount() == events.count)
    }

    @Test("Appending the same batch twice stores nothing the second time")
    func appendIsIdempotent() throws {
        let (_, events) = try openGroup()
        let store = try EventStore.inMemory()

        try store.append(events, origin: .remote)
        let afterFirst = try store.allEvents().events
        try store.append(events, origin: .remote)
        let afterSecond = try store.allEvents().events

        #expect(afterFirst == afterSecond)
        #expect(try store.eventCount() == events.count)
    }

    @Test("Local events queue for push; pulled events do not")
    func onlyLocalEventsEnterTheOutbox() throws {
        let (_, events) = try openGroup()
        let store = try EventStore.inMemory()

        try store.append(events, origin: .remote)
        #expect(try store.outboxCount() == 0)

        var factory = EventFactory()
        let local = factory.expenseCreated(Fixtures.expense(2), try wineExpense())
        try store.append([local], origin: .local)
        #expect(try store.outboxCount() == 1)
        #expect(try store.outboxBatch().events == [local])
    }

    @Test("Acknowledging stamps the sequence and clears the queue, together")
    func acknowledgeStampsAndDequeues() throws {
        let store = try EventStore.inMemory()
        let local = EventEnvelope(
            groupId: Fixtures.groupId,
            entityId: Fixtures.groupId.rawValue,
            authorId: Fixtures.authorId,
            clientTimestamp: Fixtures.timestamp,
            serverSeq: nil,
            payload: .groupCreated(GroupCreatedPayload(name: "Fjällresan", currency: .sek))
        )
        try store.append([local], origin: .local)
        #expect(try store.allEvents().events.first?.serverSeq == nil)

        try store.acknowledge([(eventId: local.eventId, serverSeq: 4711)])

        #expect(try store.outboxCount() == 0)
        #expect(try store.allEvents().events.first?.serverSeq == 4711)
        #expect(try store.eventCount() == 1)
    }

    @Test("A failed push keeps the event queued and remembers why")
    func pushFailureIsRecordedNotDropped() throws {
        let store = try EventStore.inMemory()
        var factory = EventFactory()
        let local = factory.groupCreated()
        try store.append([local], origin: .local)

        try store.recordPushFailure([local.eventId], error: "offline")

        // CLAIM: never drop outbox events silently (CLAUDE.md).
        #expect(try store.outboxCount() == 1)
        #expect(try store.outboxBatch().events == [local])
    }

    @Test("Events load in replay order however they were written")
    func loadOrderIsReplayOrder() throws {
        let (_, events) = try openGroup()
        let store = try EventStore.inMemory()

        // Written back to front, and with an unacknowledged local event in the middle.
        let pending = EventEnvelope(
            groupId: Fixtures.groupId,
            entityId: Fixtures.expense(9).rawValue,
            authorId: Fixtures.authorId,
            clientTimestamp: Fixtures.timestamp,
            serverSeq: nil,
            payload: .expenseCreated(try wineExpense())
        )
        try store.append([pending], origin: .local)
        try store.append(Array(events.reversed()), origin: .remote)

        let loaded = try store.allEvents().events
        #expect(loaded.dropLast() == events)          // acknowledged, in serverSeq order
        #expect(loaded.last == pending)               // still-queued local event, last
    }

    @Test("An event type this build cannot read survives storage intact")
    func unknownEventTypeSurvivesStorage() throws {
        var factory = EventFactory()
        let unknown = factory.unknownType("CommentAdded")
        let store = try EventStore.inMemory()

        try store.append([unknown], origin: .remote)
        let reloaded = try #require(try store.allEvents().events.first)

        // The payload has to come back whole, because a later build that understands
        // CommentAdded will rebuild from this same row and must see every field.
        #expect(reloaded == unknown)
        guard case .unknown(let type, let raw) = reloaded.payload else {
            Issue.record("Expected the unknown payload to survive, got \(reloaded.payload)")
            return
        }
        #expect(type == "CommentAdded")
        #expect(raw["someFutureField"]?.stringValue == "hello from a newer build")
    }

    @Test("Group cursors start at zero and only move forward")
    func cursorsAdvanceMonotonically() throws {
        let store = try EventStore.inMemory()
        #expect(try store.cursor(forGroup: Fixtures.groupId) == 0)

        try store.setCursor(120, forGroup: Fixtures.groupId)
        #expect(try store.cursor(forGroup: Fixtures.groupId) == 120)

        // An out-of-order ack must not rewind the cursor and re-deliver everything after it.
        try store.setCursor(40, forGroup: Fixtures.groupId)
        #expect(try store.cursor(forGroup: Fixtures.groupId) == 120)
    }

    @Test("Reading one group does not return another group's events")
    func eventsAreScopedToTheirGroup() throws {
        let (_, events) = try openGroup()
        let store = try EventStore.inMemory()
        try store.append(events, origin: .remote)

        var other = EventFactory(groupId: GroupID(), authorId: Fixtures.authorId)
        try store.append([other.groupCreated(name: "Annan grupp")], origin: .remote)

        #expect(try store.events(inGroup: Fixtures.groupId).events == events)
        #expect(try store.eventCount() == events.count + 1)
    }

    @Test("Migrating an already-migrated database changes nothing")
    func migratorIsIdempotent() throws {
        let queue = try DatabaseQueue()
        let store = try EventStore(queue)
        var factory = EventFactory()
        try store.append([factory.groupCreated()], origin: .local)

        // Same database, second EventStore: the migrator runs again on open.
        let reopened = try EventStore(queue)
        #expect(try reopened.eventCount() == 1)
        #expect(try reopened.outboxCount() == 1)
    }
}
