import Foundation
import Testing
import KvittaCoreTestSupport
@testable import KvittaCore

@Suite("Projector")
struct ProjectorTests {
    private let members = (1...3).map { Fixtures.member($0) }

    /// Carl, Jonas and Sara. Carl pays 437.00 kr for the wine and it is split equally.
    private func openGroup() throws -> (factory: EventFactory, events: [EventEnvelope]) {
        var factory = EventFactory()
        var events: [EventEnvelope] = [factory.groupCreated()]
        for (index, memberId) in members.enumerated() {
            events.append(factory.memberAdded(memberId, name: "Member \(index + 1)"))
        }
        return (factory, events)
    }

    private func wineExpense() throws -> ExpensePayload {
        try ExpensePayload.make(
            description: "Systembolaget",
            categoryId: "alkohol",
            date: Fixtures.date,
            total: Fixtures.money(43_700),
            paidBy: members[0],
            splitEquallyAmong: members
        )
    }

    @Test("Balances match the numbers you get on paper")
    func handCalculatedBalances() throws {
        var (factory, events) = try openGroup()
        events.append(factory.expenseCreated(Fixtures.expense(1), try wineExpense()))

        let state = Projector.replay(events)
        let group = try #require(state.groups[Fixtures.groupId])
        let balances = group.balances()

        #expect(balances.amountMinor(for: members[0]) == 29_133)   // 437.00 paid, 145.67 owed
        #expect(balances.amountMinor(for: members[1]) == -14_567)
        #expect(balances.amountMinor(for: members[2]) == -14_566)
        #expect(balances.totalMinor == 0)
        #expect(group.name == "Fjällresan")
        #expect(group.currency == .sek)
    }

    @Test("Recording a settle-up moves exactly that much and nothing else")
    func paymentSettlesOneDebt() throws {
        var (factory, events) = try openGroup()
        events.append(factory.expenseCreated(Fixtures.expense(1), try wineExpense()))
        events.append(
            factory.paymentRecorded(
                Fixtures.payment(1),
                try PaymentRecordedPayload(
                    fromMemberId: members[1],
                    toMemberId: members[0],
                    currency: .sek,
                    amountMinor: 14_567,
                    date: CalendarDate(year: 2026, month: 7, day: 22)!,
                    method: .swish
                )
            )
        )

        let group = try #require(Projector.replay(events).groups[Fixtures.groupId])
        let balances = group.balances()

        #expect(balances.amountMinor(for: members[0]) == 14_566)
        #expect(balances.amountMinor(for: members[1]) == 0)
        #expect(balances.amountMinor(for: members[2]) == -14_566)
        #expect(balances.totalMinor == 0)
        #expect(group.suggestedTransfers()
            == [SuggestedTransfer(from: members[2], to: members[0], amountMinor: 14_566)])
    }

    @Test("A balance can be walked line by line and lands on exactly the number shown")
    func breakdownEndsOnTheBalance() throws {
        var (factory, events) = try openGroup()
        events.append(factory.expenseCreated(Fixtures.expense(1), try wineExpense()))
        events.append(
            factory.paymentRecorded(
                Fixtures.payment(1),
                try PaymentRecordedPayload(
                    fromMemberId: members[1],
                    toMemberId: members[0],
                    currency: .sek,
                    amountMinor: 14_567,
                    date: CalendarDate(year: 2026, month: 7, day: 22)!,
                    method: .swish
                )
            )
        )

        let group = try #require(Projector.replay(events).groups[Fixtures.groupId])
        let lines = group.breakdown(for: members[0])

        #expect(lines.map(\.deltaMinor) == [29_133, -14_567])
        #expect(lines.map(\.runningTotalMinor) == [29_133, 14_566])
        #expect(lines.last?.runningTotalMinor == group.balances().amountMinor(for: members[0]))
        #expect(lines.first?.source == .expense(Fixtures.expense(1)))
        #expect(lines.last?.source == .payment(Fixtures.payment(1)))
    }

    @Test("The same event applied twice changes nothing the second time")
    func duplicateEventIsANoOp() throws {
        var (factory, events) = try openGroup()
        let expenseEvent = factory.expenseCreated(Fixtures.expense(1), try wineExpense())
        events.append(expenseEvent)

        let once = Projector.replay(events)
        let twice = Projector.apply(once, expenseEvent)

        #expect(once == twice)
        #expect(once.skipped.isEmpty)
    }

    @Test("An event type from a newer build is skipped, recorded, and harmless")
    func unknownEventTypeIsSkipped() throws {
        var (factory, events) = try openGroup()
        events.append(factory.expenseCreated(Fixtures.expense(1), try wineExpense()))
        events.append(factory.unknownType("CommentAdded"))

        let state = Projector.replay(events)
        let group = try #require(state.groups[Fixtures.groupId])

        #expect(group.balances().amountMinor(for: members[0]) == 29_133)
        #expect(state.skipped.count == 1)
        #expect(state.skipped.first?.reason == .unknownEventType("CommentAdded"))
        // Skipped is not unseen: the watermark still moved, so the cursor cannot stall on it.
        #expect(group.lastAppliedSeq == events.last?.serverSeq)
    }

    @Test("An event for a group we have never heard of is skipped")
    func eventForUnknownGroupIsSkipped() throws {
        var factory = EventFactory(groupId: GroupID(), authorId: Fixtures.authorId)
        let orphan = factory.memberAdded(members[0], name: "Nobody")

        let state = Projector.apply(.empty, orphan)
        #expect(state.groups.isEmpty)
        #expect(state.skipped.first?.reason == .unknownGroup)
    }

    @Test("Deleting an expense takes it out of the balances; restoring puts it back")
    func softDeleteAndRestore() throws {
        var (factory, events) = try openGroup()
        events.append(factory.expenseCreated(Fixtures.expense(1), try wineExpense()))

        events.append(factory.expenseDeleted(Fixtures.expense(1)))
        let afterDelete = try #require(Projector.replay(events).groups[Fixtures.groupId])
        #expect(afterDelete.balances().isSettled)
        #expect(afterDelete.visibleExpenses.isEmpty)
        #expect(afterDelete.deletedExpenses.count == 1)

        events.append(factory.expenseRestored(Fixtures.expense(1)))
        let afterRestore = try #require(Projector.replay(events).groups[Fixtures.groupId])
        #expect(afterRestore.balances().amountMinor(for: members[0]) == 29_133)
        #expect(afterRestore.visibleExpenses.count == 1)
    }

    @Test("An update replaces the whole expense and counts as a revision")
    func updateReplacesWholesale() throws {
        var (factory, events) = try openGroup()
        events.append(factory.expenseCreated(Fixtures.expense(1), try wineExpense()))

        let corrected = try ExpensePayload.make(
            description: "Systembolaget (rättad)",
            categoryId: "alkohol",
            date: Fixtures.date,
            total: Fixtures.money(30_000),
            paidBy: members[1],
            splitEquallyAmong: [members[0], members[1]]
        )
        events.append(factory.expenseUpdated(Fixtures.expense(1), corrected))

        let group = try #require(Projector.replay(events).groups[Fixtures.groupId])
        let expense = try #require(group.expenses[Fixtures.expense(1)])

        #expect(expense.revision == 1)
        #expect(expense.wasEdited)
        #expect(expense.title == "Systembolaget (rättad)")
        #expect(group.balances().amountMinor(for: members[1]) == 15_000)
        #expect(group.balances().amountMinor(for: members[2]) == 0)
        #expect(group.balances().totalMinor == 0)
    }

    @Test("A removed member keeps their balance — otherwise the books stop adding up")
    func removedMemberKeepsBalance() throws {
        var (factory, events) = try openGroup()
        events.append(factory.expenseCreated(Fixtures.expense(1), try wineExpense()))
        events.append(factory.memberRemoved(members[2]))

        let group = try #require(Projector.replay(events).groups[Fixtures.groupId])

        #expect(group.members[members[2]]?.isActive == false)
        #expect(group.activeMembers.count == 2)
        #expect(group.balances().amountMinor(for: members[2]) == -14_566)
        #expect(group.balances().totalMinor == 0)
    }

    @Test("An expense naming a member who was never added is skipped rather than guessed at")
    func expenseWithUnknownMemberIsSkipped() throws {
        var (factory, events) = try openGroup()
        let stranger = Fixtures.member(99)
        let payload = try ExpensePayload.make(
            description: "Okänd",
            categoryId: "ovrigt",
            date: Fixtures.date,
            total: Fixtures.money(1_000),
            paidBy: members[0],
            splitEquallyAmong: [members[0], stranger]
        )
        events.append(factory.expenseCreated(Fixtures.expense(2), payload))

        let state = Projector.replay(events)
        let group = try #require(state.groups[Fixtures.groupId])

        #expect(group.expenses.isEmpty)
        #expect(state.skipped.first?.reason == .unknownMember(stranger))
    }

    @Test("An expense in the wrong currency is skipped")
    func currencyMismatchIsSkipped() throws {
        var (factory, events) = try openGroup()
        let payload = try ExpensePayload(
            description: "København",
            categoryId: "restaurang",
            date: Fixtures.date,
            currency: .dkk,
            amountMinor: 1_000,
            payers: [MoneyLine(memberId: members[0], amountMinor: 1_000)],
            shares: [MoneyLine(memberId: members[0], amountMinor: 1_000)],
            splitMethod: .exact
        )
        events.append(factory.expenseCreated(Fixtures.expense(3), payload))

        let state = Projector.replay(events)
        #expect(state.groups[Fixtures.groupId]?.expenses.isEmpty == true)
        #expect(state.skipped.first?.reason == .currencyMismatch(expected: .sek, found: .dkk))
    }

    @Test("Unacknowledged local events replay after everything the server has ordered")
    func pendingEventsApplyLast() throws {
        let (_, events) = try openGroup()

        // Still in the outbox: no serverSeq yet, and it references members the synced events add.
        let localExpense = EventEnvelope(
            groupId: Fixtures.groupId,
            entityId: Fixtures.expense(4).rawValue,
            authorId: Fixtures.authorId,
            clientTimestamp: Fixtures.timestamp,
            serverSeq: nil,
            payload: .expenseCreated(try wineExpense())
        )

        // Hand the synced events over shuffled on purpose. Putting them back in serverSeq order,
        // and the pending one after them, is the projector's job — if it were not, this expense
        // would be skipped for naming members that "do not exist yet".
        let state = Projector.replay(
            synced: Array(events.reversed()),
            pending: [localExpense]
        )
        let group = try #require(state.groups[Fixtures.groupId])

        #expect(group.expenses.count == 1)
        #expect(group.balances().amountMinor(for: members[0]) == 29_133)
        #expect(group.balances().totalMinor == 0)
        #expect(state.skipped.isEmpty)
    }

    @Test("A whole log replays to the same state whether folded in one pass or many")
    func replayIsAssociative() throws {
        var (factory, events) = try openGroup()
        events.append(factory.expenseCreated(Fixtures.expense(1), try wineExpense()))
        events.append(factory.expenseDeleted(Fixtures.expense(1)))
        events.append(factory.expenseRestored(Fixtures.expense(1)))

        let inOneGo = Projector.replay(events)
        let inChunks = Projector.replay(
            Array(events.suffix(from: 2)),
            into: Projector.replay(Array(events.prefix(2)))
        )
        #expect(inOneGo == inChunks)
    }
}
