import Foundation
import Testing
import KvittaCore
@testable import Kvitta

/// The three-line card at the top of Balansgranskning — "din andel − det du betalade = …" —
/// is a *restatement* of the balance, not a second calculation of it. These tests pin the
/// relationship: whatever the card says must equal the number the hero card shows, to the öre,
/// and the same for the running total the audit list ends on. If the two ever drift, the
/// screen that exists to build trust would be the one lying.
@MainActor
struct BalanceSummaryTests {

    @Test("On the preview data every card equals the balance it explains, in every currency")
    func summaryMatchesBalancesEverywhere() {
        let ledger = PreviewLedger.populated()

        var checked = 0
        for group in ledger.state.groups.values {
            for balances in group.balances().byCurrency {
                for member in group.activeMembers {
                    guard let summary = BalanceSummary(group: group, memberId: member.id, currency: balances.currency) else {
                        continue
                    }
                    #expect(summary.resultMinor == balances.amountMinor(for: member.id))
                    #expect(summary.resultMinor == group.breakdown(for: member.id, in: balances.currency).last?.runningTotalMinor)
                    checked += 1
                }
            }
        }
        // Three people on the Malmö bill (Ellen sat that one out) and two in the flat: a loop
        // that never asserts is not a test.
        #expect(checked == 5)
    }

    @Test("Malmö: you paid the whole Systembolaget run and carry a third of it")
    func paidAndShareAreTheRealFigures() throws {
        let ledger = PreviewLedger.populated()
        let malmo = try #require(ledger.state.groups.values.first { $0.name.contains("Malmö") })
        let me = try #require(malmo.me(for: PreviewLedger.userId))

        let summary = try #require(BalanceSummary(group: malmo, memberId: me.id, currency: .sek))

        #expect(summary.paidMinor == 43_700)
        // 437 kr over three people is 145,67 or 145,66 depending on where the öre lands.
        #expect([14_566, 14_567].contains(summary.shareMinor))
        #expect(summary.sentMinor == 0)
        #expect(summary.receivedMinor == 0)
        #expect(summary.resultMinor == 43_700 - summary.shareMinor)
    }

    @Test("A settle-up that counts lands on its own line and moves the result")
    func settleUpIsNamedSeparately() throws {
        let ledger = PreviewLedger.populated()
        let apartment = try #require(ledger.state.groups.values.first { $0.name.contains("Lägenheten") })
        let me = try #require(apartment.me(for: PreviewLedger.userId))
        let alex = try #require(apartment.activeMembers.first { $0.id != me.id })

        // Old enough to have aged past the confirmation window, so it counts toward the balance
        // the way the projector counts it — the summary must follow the projector, not guess.
        let longAgo = CalendarDate(Date().addingTimeInterval(-60 * 86_400))
        try ledger.record(
            .paymentRecorded(try PaymentRecordedPayload(
                fromMemberId: me.id, toMemberId: alex.id,
                currency: .sek, amountMinor: 10_000,
                date: longAgo, method: PaymentMethod(rawValue: "swish")
            )),
            entityId: PaymentID().rawValue, in: apartment.id
        )

        let after = try #require(ledger.state[apartment.id])
        let summary = try #require(BalanceSummary(group: after, memberId: me.id, currency: .sek))

        #expect(summary.shareMinor == 15_200)
        #expect(summary.paidMinor == 0)
        #expect(summary.sentMinor == 10_000)
        #expect(summary.resultMinor == -5_200)
        #expect(summary.resultMinor == after.balances().byCurrency.first { $0.currency == .sek }?.amountMinor(for: me.id))
    }
}
