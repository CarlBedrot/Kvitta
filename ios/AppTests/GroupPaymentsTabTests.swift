import Testing
import Foundation
import KvittaCore
@testable import Kvitta

/// `PaymentDisplayStatus` is the one piece of `GroupPaymentsTab` that is pure enough to test
/// without a simulator: the same four dates `PaymentConfirmationTests.autoConfirmAges` (Core)
/// exercises against `countsTowardBalances`, read back as the word the BETALNINGAR card shows.
struct GroupPaymentsTabTests {
    private func payment(status: PaymentStatus, date: CalendarDate) throws -> Payment {
        Payment(
            id: PaymentID(),
            payload: try PaymentRecordedPayload(
                fromMemberId: MemberID(),
                toMemberId: MemberID(),
                currency: .sek,
                amountMinor: 1_000,
                date: date,
                method: .swish
            ),
            recordedBy: UserID(),
            recordedAt: Timestamp(Date()),
            status: status
        )
    }

    @Test func confirmedIsAlwaysConfirmed() throws {
        let date = CalendarDate(year: 2026, month: 7, day: 21)!
        let recorded = try payment(status: .confirmed, date: date)
        #expect(PaymentDisplayStatus(recorded, asOf: date) == .confirmed)
    }

    @Test func disputedIsAlwaysDisputed() throws {
        let date = CalendarDate(year: 2026, month: 7, day: 21)!
        let muchLater = CalendarDate(year: 2026, month: 9, day: 1)!
        let recorded = try payment(status: .disputed, date: date)
        #expect(PaymentDisplayStatus(recorded, asOf: muchLater) == .disputed)
    }

    @Test func pendingWaitsUntilTheAutoConfirmWindowThenFlips() throws {
        let recordedOn = CalendarDate(year: 2026, month: 7, day: 21)!
        let sixDaysLater = CalendarDate(year: 2026, month: 7, day: 27)!
        let sevenDaysLater = CalendarDate(year: 2026, month: 7, day: 28)!
        let recorded = try payment(status: .pending, date: recordedOn)

        #expect(PaymentDisplayStatus(recorded, asOf: sixDaysLater) == .waiting)
        #expect(PaymentDisplayStatus(recorded, asOf: sevenDaysLater) == .autoConfirmed)
    }
}
