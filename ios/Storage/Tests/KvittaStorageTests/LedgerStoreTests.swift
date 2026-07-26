import Foundation
import Testing
import KvittaCore
import KvittaCoreTestSupport
@testable import KvittaStorage

@Suite("LedgerStore")
@MainActor
struct LedgerStoreTests {
    private let members = (1...3).map { Fixtures.member($0) }

    private func makeStore() throws -> LedgerStore {
        LedgerStore(
            store: try EventStore.inMemory(now: { Fixtures.timestamp }),
            authorId: Fixtures.authorId,
            now: { Fixtures.timestamp }
        )
    }

    /// Builds the group the projector tests use: three members, one 437.00 kr expense split
    /// equally, paid by the first member.
    @discardableResult
    private func seed(_ ledger: LedgerStore) throws -> GroupID {
        let groupId = Fixtures.groupId
        try ledger.record(
            .groupCreated(GroupCreatedPayload(name: "Fjällresan", currency: .sek)),
            entityId: groupId.rawValue,
            in: groupId
        )
        for (index, memberId) in members.enumerated() {
            try ledger.record(
                .memberAdded(MemberAddedPayload(displayName: "Member \(index + 1)")),
                entityId: memberId.rawValue,
                in: groupId
            )
        }
        let expense = try ExpensePayload.make(
            description: "Systembolaget",
            categoryId: "alkohol",
            date: Fixtures.date,
            total: Money(amountMinor: 43_700, currency: .sek),
            paidBy: members[0],
            splitEquallyAmong: members
        )
        try ledger.record(
            .expenseCreated(expense),
            entityId: Fixtures.expense(1).rawValue,
            in: groupId
        )
        return groupId
    }

    @Test("Recording an event updates the projection and the log in one call")
    func recordWritesBothHalves() throws {
        let ledger = try makeStore()
        let groupId = try seed(ledger)

        let group = try #require(ledger.state.groups[groupId])
        #expect(group.balances().amountMinor(for: members[0]) == 29_133)
        #expect(group.balances().totalMinor == 0)
        // Everything written locally is queued for push; nothing is lost if the app dies here.
        #expect(try ledger.pendingPushCount() == 5)
    }

    @Test("A relaunch reproduces exactly what was on screen before")
    func stateSurvivesARelaunch() throws {
        let store = try EventStore.inMemory(now: { Fixtures.timestamp })
        let first = LedgerStore(store: store, authorId: Fixtures.authorId, now: { Fixtures.timestamp })
        let groupId = try seed(first)

        // Same database, a brand new store — this is what launching the app does.
        let second = LedgerStore(store: store, authorId: Fixtures.authorId, now: { Fixtures.timestamp })
        try second.rebuild()

        #expect(second.state == first.state)
        #expect(second.state.groups[groupId]?.balances().amountMinor(for: members[0]) == 29_133)
    }

    @Test("Rebuilding from the log changes nothing — it is the launch path, not a repair tool")
    func rebuildIsIdempotent() throws {
        let ledger = try makeStore()
        try seed(ledger)
        let before = ledger.state

        try ledger.rebuild()
        #expect(ledger.state == before)

        try ledger.rebuild()
        #expect(ledger.state == before)
    }

    @Test("A rejected write leaves the projection untouched")
    func failedWriteDoesNotUpdateState() throws {
        let ledger = try makeStore()
        try seed(ledger)
        let before = ledger.state

        // An expense naming somebody who is not in the group. It reaches the log — the log takes
        // anything well-formed — but the projector refuses it, so no balance moves.
        let stranger = Fixtures.member(99)
        let orphan = try ExpensePayload.make(
            description: "Okänd",
            categoryId: "ovrigt",
            date: Fixtures.date,
            total: Money(amountMinor: 1_000, currency: .sek),
            paidBy: members[0],
            splitEquallyAmong: [members[0], stranger]
        )
        try ledger.record(
            .expenseCreated(orphan),
            entityId: Fixtures.expense(2).rawValue,
            in: Fixtures.groupId
        )

        #expect(ledger.state.groups[Fixtures.groupId]?.expenses.count
            == before.groups[Fixtures.groupId]?.expenses.count)
        #expect(ledger.state.skipped.count == 1)
        #expect(ledger.state.groups[Fixtures.groupId]?.balances().totalMinor == 0)
    }

    @Test("Pulled events are folded in and acknowledged ones leave the queue")
    func integrateAndAcknowledge() throws {
        let ledger = try makeStore()
        try seed(ledger)

        let queued = try ledger.outboxBatch()
        #expect(queued.count == 5)

        try ledger.acknowledge(
            queued.enumerated().map { (eventId: $1.eventId, serverSeq: Int64($0 + 1)) }
        )

        #expect(try ledger.pendingPushCount() == 0)
        #expect(ledger.state.groups[Fixtures.groupId]?.lastAppliedSeq == 5)
        // Acknowledgement is bookkeeping: the money must not move.
        #expect(ledger.state.groups[Fixtures.groupId]?.balances().amountMinor(for: members[0])
            == 29_133)
    }

    @Test("The app works with no database content at all")
    func emptyLedgerLoads() throws {
        let ledger = try makeStore()
        try ledger.rebuild()

        #expect(ledger.state == .empty)
        #expect(ledger.rejected.isEmpty)
        #expect(try ledger.pendingPushCount() == 0)
    }
}
