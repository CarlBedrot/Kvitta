import Foundation
import Testing
import KvittaCoreTestSupport
@testable import KvittaCore

/// What is worth interrupting somebody about.
@Suite("Reminder planner")
struct ReminderPlannerTests {
    private let members = (1...3).map { Fixtures.member($0) }
    private let me = UserID(uuidString: "00000000-0000-0000-00ee-000000000001")!

    /// 437.00 kr paid by `payer`, split equally three ways. `meIndex` is which member is us.
    private func group(payer: Int, meIndex: Int) throws -> LedgerState {
        var factory = EventFactory()
        var events: [EventEnvelope] = [factory.groupCreated(name: "Fjällresan")]

        for (index, memberId) in members.enumerated() {
            events.append(factory.memberAdded(
                memberId,
                name: "Member \(index + 1)",
                linkedUserId: index == meIndex ? me : nil
            ))
        }

        events.append(factory.expenseCreated(Fixtures.expense(1), try ExpensePayload.make(
            description: "Systembolaget",
            categoryId: "alkohol",
            date: Fixtures.date,
            total: Money(amountMinor: 43_700, currency: .sek),
            paidBy: members[payer],
            splitEquallyAmong: members
        )))

        return Projector.replay(events)
    }

    @Test("Owing money is worth a reminder")
    func owingIsReminded() throws {
        // Somebody else paid, so we owe our share.
        let reminder = try #require(
            ReminderPlanner.outstanding(in: try group(payer: 0, meIndex: 1), for: me).first
        )

        #expect(reminder.groupName == "Fjällresan")
        #expect(reminder.owed.amountMinor == 14_567)
        #expect(reminder.owed.currency == .sek)
    }

    @Test("Being owed money is never a reminder")
    func beingOwedIsNotReminded() throws {
        // We paid, so we are owed. Reminding here would nag two other people through our phone,
        // on a schedule they never agreed to, about a number they cannot see.
        let state = try group(payer: 0, meIndex: 0)

        #expect(ReminderPlanner.outstanding(in: state, for: me).isEmpty)
    }

    @Test("Settled is silence")
    func settledIsSilent() throws {
        var factory = EventFactory()
        var events: [EventEnvelope] = [factory.groupCreated()]
        for (index, memberId) in members.enumerated() {
            events.append(factory.memberAdded(
                memberId, name: "M\(index)", linkedUserId: index == 1 ? me : nil
            ))
        }
        events.append(factory.expenseCreated(Fixtures.expense(1), try ExpensePayload.make(
            description: "Middag", categoryId: "restaurang", date: Fixtures.date,
            total: Money(amountMinor: 30_000, currency: .sek),
            paidBy: members[0], splitEquallyAmong: [members[0], members[1]]
        )))
        // And then we pay it back.
        events.append(factory.paymentRecorded(Fixtures.payment(1), try PaymentRecordedPayload(
            fromMemberId: members[1], toMemberId: members[0],
            currency: .sek, amountMinor: 15_000,
            date: Fixtures.date, method: .swish
        )))

        // Settled is the state the whole app is trying to reach. Never interrupt anyone about it.
        #expect(ReminderPlanner.outstanding(in: Projector.replay(events), for: me).isEmpty)
    }

    @Test("Somebody with no member in the group is not reminded about it")
    func strangersAreNotReminded() throws {
        let state = try group(payer: 0, meIndex: 1)
        let somebodyElse = UserID()

        #expect(ReminderPlanner.outstanding(in: state, for: somebodyElse).isEmpty)
    }

    @Test("A pending payment does not silence the debt until it counts")
    func pendingPaymentKeepsTheDebt() throws {
        let payeeUser = UserID(uuidString: "00000000-0000-0000-00ee-000000000002")!
        var factory = EventFactory()
        var events: [EventEnvelope] = [
            factory.groupCreated(),
            factory.memberAdded(members[0], name: "Sara", linkedUserId: payeeUser),
            factory.memberAdded(members[1], name: "Me", linkedUserId: me)
        ]
        events.append(factory.expenseCreated(Fixtures.expense(1), try ExpensePayload.make(
            description: "Middag", categoryId: "restaurang", date: Fixtures.date,
            total: Money(amountMinor: 30_000, currency: .sek),
            paidBy: members[0], splitEquallyAmong: [members[0], members[1]]
        )))
        // I say I paid Sara. Pending until she answers — so on paper I still owe.
        events.append(factory.paymentRecorded(Fixtures.payment(1), try PaymentRecordedPayload(
            fromMemberId: members[1], toMemberId: members[0],
            currency: .sek, amountMinor: 15_000,
            date: Fixtures.date, method: .swish
        )))
        let state = Projector.replay(events)

        #expect(ReminderPlanner.outstanding(in: state, for: me, asOf: Fixtures.date).count == 1)

        // Aged past the auto-confirm window it counts, and the reminder goes quiet.
        let aged = CalendarDate(year: 2026, month: 7, day: 28)!
        #expect(ReminderPlanner.outstanding(in: state, for: me, asOf: aged).isEmpty)

        // The nudge mirrors it exactly: Sara is asked while the question is open, nobody after.
        #expect(
            ReminderPlanner.awaitingMyConfirmation(in: state, for: payeeUser, asOf: Fixtures.date)
                .map(\.paymentId) == [Fixtures.payment(1)]
        )
        #expect(ReminderPlanner.awaitingMyConfirmation(in: state, for: me, asOf: Fixtures.date).isEmpty)
        #expect(ReminderPlanner.awaitingMyConfirmation(in: state, for: payeeUser, asOf: aged).isEmpty)
    }

    @Test("The biggest debt comes first, and ties do not shuffle")
    func orderingIsStable() throws {
        var factory = EventFactory()
        var events: [EventEnvelope] = []

        // Two groups, different debts.
        for (groupIndex, total) in [(0, Int64(10_000)), (1, Int64(50_000))] {
            var groupFactory = EventFactory(groupId: GroupID(), authorId: Fixtures.authorId)
            let pair = [Fixtures.member(10 + groupIndex), Fixtures.member(20 + groupIndex)]
            events.append(groupFactory.groupCreated(name: "G\(groupIndex)"))
            events.append(groupFactory.memberAdded(pair[0], name: "Payer"))
            events.append(groupFactory.memberAdded(pair[1], name: "Me", linkedUserId: me))
            events.append(groupFactory.expenseCreated(ExpenseID(), try ExpensePayload.make(
                description: "X", categoryId: "ovrigt", date: Fixtures.date,
                total: Money(amountMinor: total, currency: .sek),
                paidBy: pair[0], splitEquallyAmong: pair
            )))
        }
        _ = factory

        let reminders = ReminderPlanner.outstanding(in: Projector.replay(events), for: me)

        #expect(reminders.count == 2)
        #expect(reminders[0].owed.amountMinor == 25_000)
        #expect(reminders[1].owed.amountMinor == 5_000)
    }
}
