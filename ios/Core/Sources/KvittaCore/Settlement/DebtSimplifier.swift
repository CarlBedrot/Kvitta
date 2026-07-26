import Foundation

/// One suggested "you pay them this much" line. Display only — settling still requires the user
/// to actually move money and confirm, which writes a `PaymentRecorded` event.
public struct SuggestedTransfer: Hashable, Sendable {
    public let from: MemberID
    public let to: MemberID
    public let amountMinor: Int64

    public init(from: MemberID, to: MemberID, amountMinor: Int64) {
        self.from = from
        self.to = to
        self.amountMinor = amountMinor
    }
}

/// Turns a set of balances into the fewest sensible transfers that clear them.
///
/// Greedy largest-debtor against largest-creditor (design doc §4). Not provably minimal — that is
/// NP-hard and nobody splitting a dinner cares — but it is at most `n-1` transfers, it is
/// deterministic, and property test P4 proves that applying every transfer it suggests leaves
/// every balance at exactly zero.
///
/// It creates no events. Balances are the source of truth; this is a suggestion drawn on top.
public enum DebtSimplifier {

    public static func simplify(_ balances: Balances) -> [SuggestedTransfer] {
        simplify(balances.byMember)
    }

    public static func simplify(_ byMember: [MemberID: Int64]) -> [SuggestedTransfer] {
        // A named struct rather than a labelled tuple: the tuple version of this chain sends
        // Swift's expression type checker into the weeds and takes minutes to compile.
        struct Side {
            let memberId: MemberID
            var remaining: Int64
        }

        // Ties broken on memberId at every step, so two devices with identical balances suggest
        // identical transfers — otherwise "Gör upp" would say different things to two people
        // looking at the same screen.
        func sides(matching include: (Int64) -> Bool, magnitude: (Int64) -> Int64) -> [Side] {
            var result: [Side] = []
            for (memberId, balance) in byMember where include(balance) {
                result.append(Side(memberId: memberId, remaining: magnitude(balance)))
            }
            result.sort { left, right in
                left.remaining == right.remaining
                    ? left.memberId < right.memberId
                    : left.remaining > right.remaining
            }
            return result
        }

        var debtors: [Side] = sides(matching: { $0 < 0 }, magnitude: { -$0 })
        var creditors: [Side] = sides(matching: { $0 > 0 }, magnitude: { $0 })

        var transfers: [SuggestedTransfer] = []
        var debtorIndex = 0
        var creditorIndex = 0

        while debtorIndex < debtors.count && creditorIndex < creditors.count {
            let amount = Swift.min(debtors[debtorIndex].remaining, creditors[creditorIndex].remaining)

            transfers.append(
                SuggestedTransfer(
                    from: debtors[debtorIndex].memberId,
                    to: creditors[creditorIndex].memberId,
                    amountMinor: amount
                )
            )

            debtors[debtorIndex].remaining -= amount
            creditors[creditorIndex].remaining -= amount

            // Each pass zeroes at least one side, so at most (debtors + creditors - 1) transfers
            // are emitted — the n-1 bound.
            if debtors[debtorIndex].remaining == 0 { debtorIndex += 1 }
            if creditors[creditorIndex].remaining == 0 { creditorIndex += 1 }
        }

        return transfers
    }
}
