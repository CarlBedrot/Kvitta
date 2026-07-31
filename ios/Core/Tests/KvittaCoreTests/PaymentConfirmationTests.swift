import Foundation
import Testing
import KvittaCoreTestSupport
@testable import KvittaCore

/// The two-sided settle-up (M8): a payment recorded *at* someone with an account is pending
/// until they answer, and only their answer counts.
@Suite("Payment confirmation")
struct PaymentConfirmationTests {

    private let payeeUser = UserID(uuidString: "00000000-0000-0000-000b-000000000002")!

    /// A group where member(1) is the author's and member(2) belongs to `payeeUser`.
    private func makeGroup(_ factory: inout EventFactory) -> [EventEnvelope] {
        [
            factory.groupCreated(),
            factory.memberAdded(Fixtures.member(1), name: "Du", linkedUserId: Fixtures.authorId),
            factory.memberAdded(Fixtures.member(2), name: "Sara", linkedUserId: payeeUser),
            factory.memberAdded(Fixtures.member(3), name: "Placeholder")
        ]
    }

    private func payment(to payee: MemberID, on date: CalendarDate = Fixtures.date) throws -> PaymentRecordedPayload {
        try PaymentRecordedPayload(
            fromMemberId: Fixtures.member(1),
            toMemberId: payee,
            currency: Fixtures.currency,
            amountMinor: 10_000,
            date: date,
            method: .swish
        )
    }

    @Test("A payment to a linked payee is born pending and moves no money")
    func bornPending() throws {
        var factory = EventFactory()
        var events = makeGroup(&factory)
        events.append(factory.paymentRecorded(Fixtures.payment(1), try payment(to: Fixtures.member(2))))

        let group = try #require(Projector.replay(events).groups[Fixtures.groupId])
        let recorded = try #require(group.payments[Fixtures.payment(1)])
        #expect(recorded.status == .pending)
        // Nothing moved: the payer still stands where the (empty) expense history left them.
        #expect(group.primaryBalances(asOf: Fixtures.date).amountMinor(for: Fixtures.member(1)) == 0)
        #expect(group.paymentsAwaitingConfirmation(asOf: Fixtures.date).map(\.id) == [Fixtures.payment(1)])
    }

    @Test("A payment to a placeholder is born confirmed — nobody could ever press the button")
    func placeholderPayeeIsConfirmed() throws {
        var factory = EventFactory()
        var events = makeGroup(&factory)
        events.append(factory.paymentRecorded(Fixtures.payment(1), try payment(to: Fixtures.member(3))))

        let group = try #require(Projector.replay(events).groups[Fixtures.groupId])
        #expect(group.payments[Fixtures.payment(1)]?.status == .confirmed)
        #expect(group.primaryBalances(asOf: Fixtures.date).amountMinor(for: Fixtures.member(1)) == 10_000)
    }

    @Test("The payee recording the payment themselves is its own confirmation")
    func selfRecordedIsConfirmed() throws {
        var factory = EventFactory()
        var events = makeGroup(&factory)
        events.append(factory.paymentRecorded(
            Fixtures.payment(1),
            try payment(to: Fixtures.member(2)),
            author: payeeUser
        ))

        let group = try #require(Projector.replay(events).groups[Fixtures.groupId])
        #expect(group.payments[Fixtures.payment(1)]?.status == .confirmed)
    }

    @Test("The payee's confirmation makes it count; their dispute takes it back out")
    func confirmAndDispute() throws {
        var factory = EventFactory()
        var events = makeGroup(&factory)
        events.append(factory.paymentRecorded(Fixtures.payment(1), try payment(to: Fixtures.member(2))))
        events.append(factory.paymentConfirmed(Fixtures.payment(1), by: payeeUser))

        var group = try #require(Projector.replay(events).groups[Fixtures.groupId])
        #expect(group.payments[Fixtures.payment(1)]?.status == .confirmed)
        #expect(group.primaryBalances(asOf: Fixtures.date).amountMinor(for: Fixtures.member(1)) == 10_000)

        // Last event wins: the payee can change their mind in either direction.
        events.append(factory.paymentDisputed(Fixtures.payment(1), by: payeeUser))
        group = try #require(Projector.replay(events).groups[Fixtures.groupId])
        #expect(group.payments[Fixtures.payment(1)]?.status == .disputed)
        #expect(group.primaryBalances(asOf: Fixtures.date).amountMinor(for: Fixtures.member(1)) == 0)
        // Disputed is an answer, not a question: it no longer awaits anyone.
        #expect(group.paymentsAwaitingConfirmation(asOf: Fixtures.date).isEmpty)
    }

    @Test("A confirmation from anyone but the payee is skipped as forged")
    func forgedConfirmationIsSkipped() throws {
        var factory = EventFactory()
        var events = makeGroup(&factory)
        events.append(factory.paymentRecorded(Fixtures.payment(1), try payment(to: Fixtures.member(2))))
        // The payer confirming their own payment is exactly the one-sidedness M8 removes.
        events.append(factory.paymentConfirmed(Fixtures.payment(1), by: Fixtures.authorId))

        let state = Projector.replay(events)
        let group = try #require(state.groups[Fixtures.groupId])
        #expect(group.payments[Fixtures.payment(1)]?.status == .pending)
        #expect(state.skipped.contains { $0.reason == .notThePayee(Fixtures.payment(1)) })
    }

    @Test("A confirmation for a payment that does not exist is skipped, never a crash")
    func confirmationForUnknownPaymentIsSkipped() throws {
        var factory = EventFactory()
        var events = makeGroup(&factory)
        events.append(factory.paymentConfirmed(Fixtures.payment(9), by: payeeUser))

        let state = Projector.replay(events)
        #expect(state.skipped.contains { $0.reason == .unknownPayment(Fixtures.payment(9)) })
    }

    @Test("A pending payment ages into counting after exactly the auto-confirm window")
    func autoConfirmAges() throws {
        var factory = EventFactory()
        var events = makeGroup(&factory)
        let recordedOn = CalendarDate(year: 2026, month: 7, day: 21)!
        events.append(factory.paymentRecorded(Fixtures.payment(1), try payment(to: Fixtures.member(2), on: recordedOn)))

        let group = try #require(Projector.replay(events).groups[Fixtures.groupId])
        let dayBefore = CalendarDate(year: 2026, month: 7, day: 27)!   // six days later
        let dayOf = CalendarDate(year: 2026, month: 7, day: 28)!       // seven days later

        #expect(group.primaryBalances(asOf: dayBefore).amountMinor(for: Fixtures.member(1)) == 0)
        #expect(group.primaryBalances(asOf: dayOf).amountMinor(for: Fixtures.member(1)) == 10_000)
        // Aged out means no longer waiting on anyone — the nudge disappears with it.
        #expect(!group.paymentsAwaitingConfirmation(asOf: dayOf).contains { $0.id == Fixtures.payment(1) })

        // A dispute beats the clock: aging is a default, not an override of the payee's word.
        events.append(factory.paymentDisputed(Fixtures.payment(1), by: payeeUser))
        let disputed = try #require(Projector.replay(events).groups[Fixtures.groupId])
        #expect(disputed.primaryBalances(asOf: dayOf).amountMinor(for: Fixtures.member(1)) == 0)
    }

    @Test("dayNumber does calendar arithmetic across month and leap boundaries")
    func dayNumberArithmetic() throws {
        let newYearsEve = CalendarDate(year: 2027, month: 12, day: 31)!
        let newYear = CalendarDate(year: 2028, month: 1, day: 1)!
        #expect(newYear.dayNumber - newYearsEve.dayNumber == 1)

        let leapFeb = CalendarDate(year: 2028, month: 2, day: 28)!
        let leapDay = CalendarDate(year: 2028, month: 2, day: 29)!
        let march = CalendarDate(year: 2028, month: 3, day: 1)!
        #expect(leapDay.dayNumber - leapFeb.dayNumber == 1)
        #expect(march.dayNumber - leapDay.dayNumber == 1)

        #expect(CalendarDate(year: 1970, month: 1, day: 1)!.dayNumber == 0)
    }
}
