import Foundation

/// Turns what the user typed into resolved shares in minor units.
///
/// Every mode funnels through `Allocator`, so all four inherit the same remainder rule. The
/// result is stored on the event and is never recomputed — this type runs once, at expense
/// creation, on the device that created it.
public enum SplitCalculator {
    public static func resolve(total: Money, input: SplitInput) throws -> [MoneyLine] {
        try resolve(totalMinor: total.amountMinor, input: input)
    }

    public static func resolve(totalMinor: Int64, input: SplitInput) throws -> [MoneyLine] {
        guard totalMinor > 0 else {
            throw CoreError.nonPositiveAmount(field: "amountMinor", value: totalMinor)
        }

        switch input {
        case .equal(let members):
            guard !members.isEmpty else { throw CoreError.emptySplit }
            let weights = members.map { WeightLine(memberId: $0, weight: 1) }
            return try Allocator.allocate(totalMinor: totalMinor, weights: weights)

        case .exact(let amounts):
            guard !amounts.isEmpty else { throw CoreError.emptySplit }
            try amounts.requireUniqueMembers(field: "exact split")
            for line in amounts where line.amountMinor < 0 {
                throw CoreError.negativeShare(memberId: line.memberId, value: line.amountMinor)
            }
            let sum = try amounts.totalMinor(context: "exact split")
            guard sum == totalMinor else {
                throw CoreError.exactSplitMismatch(expected: totalMinor, found: sum)
            }
            // Already resolved by definition; only the ordering needs normalising.
            return amounts.sortedByMember

        case .percentage(let points):
            guard !points.isEmpty else { throw CoreError.emptySplit }
            try points.requireUniqueWeightMembers()
            for line in points where line.weight < 0 {
                throw CoreError.invalidSplitWeights(
                    reason: "member \(line.memberId) has negative percentage \(line.weight) bp"
                )
            }
            let sum = try Money.sum(points.map(\.weight), context: "percentage basis points")
            guard sum == SplitInput.percentageTotalBasisPoints else {
                throw CoreError.invalidSplitWeights(
                    reason: "percentages must total \(SplitInput.percentageTotalBasisPoints) "
                          + "basis points (100%), got \(sum)"
                )
            }
            return try Allocator.allocate(totalMinor: totalMinor, weights: points)

        case .shares(let weights):
            guard !weights.isEmpty else { throw CoreError.emptySplit }
            return try Allocator.allocate(totalMinor: totalMinor, weights: weights)

        case .unrecognized:
            throw CoreError.invalidSplitWeights(
                reason: "split mode \"\(input.method)\" is not understood by this build"
            )
        }
    }
}
