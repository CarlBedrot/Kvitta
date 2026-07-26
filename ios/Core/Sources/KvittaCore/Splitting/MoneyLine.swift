import Foundation

/// One member's amount in minor units. Used for payers, resolved shares, and exact split input.
public struct MoneyLine: Hashable, Sendable, Codable {
    public let memberId: MemberID
    public let amountMinor: Int64

    public init(memberId: MemberID, amountMinor: Int64) {
        self.memberId = memberId
        self.amountMinor = amountMinor
    }
}

/// One member's relative weight in a split: basis points for percentage, share count for shares.
public struct WeightLine: Hashable, Sendable, Codable {
    public let memberId: MemberID
    public let weight: Int64

    public init(memberId: MemberID, weight: Int64) {
        self.memberId = memberId
        self.weight = weight
    }
}

extension Array where Element == MoneyLine {
    /// Deterministic order for storage and comparison. Never rely on dictionary iteration order.
    var sortedByMember: [MoneyLine] {
        sorted { $0.memberId < $1.memberId }
    }

    func totalMinor(context: String) throws -> Int64 {
        try Money.sum(map(\.amountMinor), context: context)
    }

    /// Throws on the first member that appears twice.
    func requireUniqueMembers(field: String) throws {
        var seen = Set<MemberID>(minimumCapacity: count)
        for line in self where !seen.insert(line.memberId).inserted {
            throw CoreError.duplicateMember(memberId: line.memberId, field: field)
        }
    }
}
