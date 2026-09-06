import Foundation
import KvittaCore

/// The one-sentence answer to "why do I owe this?": what your share of the expenses came to,
/// what you actually paid, and the difference — before the audit list gets into every line.
///
/// This is a *regrouping* of `GroupState.breakdown(for:in:)`, not a calculation of its own.
/// Every entry the breakdown counts is walked once and sorted onto a side: an expense's share
/// and payment come from the expense's own resolved payload (the same `share(of:)` and
/// `paid(by:)` the projector uses), and a settle-up that has started counting lands on a line
/// of its own, named as a payment rather than folded into "paid". Because each expense's delta
/// in the breakdown *is* `paid − share`, `resultMinor` equals the breakdown's last running total
/// by construction — which is exactly the number the hero card shows. The tests pin that.
struct BalanceSummary: Equatable {
    let currency: CurrencyCode
    /// Σ of this member's share across the counted expenses in `currency`.
    let shareMinor: Int64
    /// Σ of what this member paid for those expenses.
    let paidMinor: Int64
    /// Settle-ups this member has sent that count toward the balance.
    let sentMinor: Int64
    /// Settle-ups this member has received that count toward the balance.
    let receivedMinor: Int64

    /// Positive: owed. Negative: owes. Same sign convention as `Balances.amountMinor(for:)`.
    var resultMinor: Int64 { paidMinor + sentMinor - shareMinor - receivedMinor }

    /// `nil` when there is nothing to explain — the sheet shows its "no expenses yet" line.
    init?(
        group: GroupState,
        memberId: MemberID,
        currency: CurrencyCode,
        asOf: CalendarDate = CalendarDate(Date())
    ) {
        let entries = group.breakdown(for: memberId, in: currency, asOf: asOf)
        guard !entries.isEmpty else { return nil }

        var share: Int64 = 0
        var paid: Int64 = 0
        var sent: Int64 = 0
        var received: Int64 = 0

        for entry in entries {
            switch entry.source {
            case .expense(let id):
                // The breakdown already decided this expense counts (not deleted, right
                // currency, involves the member); read the two halves it netted.
                guard let payload = group.expenses[id]?.payload else { continue }
                share += payload.share(of: memberId)
                paid += payload.paid(by: memberId)
            case .payment:
                // The breakdown's delta is signed from the member's point of view: sending
                // money moves you toward being owed, receiving it the other way.
                if entry.deltaMinor > 0 {
                    sent += entry.deltaMinor
                } else {
                    received += -entry.deltaMinor
                }
            }
        }

        self.currency = currency
        self.shareMinor = share
        self.paidMinor = paid
        self.sentMinor = sent
        self.receivedMinor = received
    }
}
