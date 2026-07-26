import Foundation

/// Splits an integer amount across weighted members with a deterministic remainder rule.
///
/// This is the single place in the package where a division of money happens, and the rule is
/// fixed by `docs/expense-app-sync-design.md` §3: floor every share, then hand the leftover minor
/// units out one at a time to members in ascending `memberId` order.
///
/// The determinism is the point. 437.00 kr split three ways is 145.67 + 145.67 + 145.66, and it
/// is the *same* member who gets the extra öre on every device that ever computes it. Shares are
/// resolved once, stored on the event, and never recomputed — but replay of an old log must still
/// reproduce the same answer, and property test P2 holds this to it.
public enum Allocator {
    /// Distributes `totalMinor` across `weights` proportionally.
    ///
    /// - Returns: one line per input member, sorted by `memberId`, summing to exactly `totalMinor`.
    public static func allocate(
        totalMinor: Int64,
        weights: [WeightLine]
    ) throws -> [MoneyLine] {
        guard !weights.isEmpty else { throw CoreError.emptySplit }
        guard totalMinor >= 0 else {
            throw CoreError.nonPositiveAmount(field: "amountMinor", value: totalMinor)
        }
        try weights.requireUniqueWeightMembers()

        for line in weights where line.weight < 0 {
            throw CoreError.invalidSplitWeights(
                reason: "member \(line.memberId) has negative weight \(line.weight)"
            )
        }

        let totalWeight = try Money.sum(weights.map(\.weight), context: "split weights")
        guard totalWeight > 0 else {
            throw CoreError.invalidSplitWeights(reason: "weights must add up to more than zero")
        }

        // Sorting first is what makes the remainder assignment reproducible.
        let ordered = weights.sorted { $0.memberId < $1.memberId }

        var lines: [MoneyLine] = []
        lines.reserveCapacity(ordered.count)
        var allocated: Int64 = 0

        for line in ordered {
            let (product, overflowed) = totalMinor.multipliedReportingOverflow(by: line.weight)
            guard !overflowed else {
                throw CoreError.amountOverflow(context: "share for member \(line.memberId)")
            }
            // Both operands are non-negative, so this floors.
            let base = product / totalWeight
            allocated += base
            lines.append(MoneyLine(memberId: line.memberId, amountMinor: base))
        }

        // Flooring can only ever leave us short, and by less than one minor unit per member.
        var remainder = totalMinor - allocated
        var index = 0
        while remainder > 0 && index < lines.count {
            let line = lines[index]
            lines[index] = MoneyLine(memberId: line.memberId, amountMinor: line.amountMinor + 1)
            remainder -= 1
            index += 1
        }

        return lines
    }
}

extension Array where Element == WeightLine {
    func requireUniqueWeightMembers() throws {
        var seen = Set<MemberID>(minimumCapacity: count)
        for line in self where !seen.insert(line.memberId).inserted {
            throw CoreError.duplicateMember(memberId: line.memberId, field: "split weights")
        }
    }
}
