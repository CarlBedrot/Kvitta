import Foundation

/// The read model used by screens that compare balances across groups.
///
/// Groups remain independent books. This adapter only combines rows inside the same currency,
/// which keeps the UI from accidentally adding SEK and DKK or choosing a dictionary entry at
/// random.
public struct BalanceBook: Sendable, Hashable {
    public struct GroupSlice: Sendable, Hashable {
        public let name: String
        public let balances: GroupBalances
        public let members: [MemberID: Member]

        public init(name: String, balances: GroupBalances, members: [MemberID: Member]) {
            self.name = name
            self.balances = balances
            self.members = members
        }
    }

    public struct Summary: Sendable, Hashable {
        public let currency: CurrencyCode
        public let receivableMinor: Int64
        public let payableMinor: Int64

        public var netMinor: Int64 { receivableMinor - payableMinor }
        public var hasOpenBalances: Bool { receivableMinor != 0 || payableMinor != 0 }

        public init(currency: CurrencyCode, receivableMinor: Int64, payableMinor: Int64) {
            self.currency = currency
            self.receivableMinor = receivableMinor
            self.payableMinor = payableMinor
        }
    }

    public struct Person: Sendable, Hashable, Identifiable {
        public let identity: String
        public let memberIds: [MemberID]
        public let name: String
        public let currency: CurrencyCode
        /// Positive means this person should pay the user; negative means the user should pay them.
        public let amountMinor: Int64
        /// Gross directions remain independent: separate groups cannot settle each other.
        public let receivableMinor: Int64
        public let payableMinor: Int64
        public let groupCount: Int
        public let hasOpenBalance: Bool

        public var id: String { "\(identity)-\(currency.code)" }
        public var isReceivable: Bool { amountMinor > 0 }
        public var context: String { groupCount == 1 ? "1 grupp" : "\(groupCount) grupper" }

        public init(identity: String, memberIds: [MemberID], name: String, currency: CurrencyCode,
                    amountMinor: Int64, groupCount: Int, hasOpenBalance: Bool = true,
                    receivableMinor: Int64? = nil, payableMinor: Int64? = nil) {
            self.identity = identity
            self.memberIds = memberIds
            self.name = name
            self.currency = currency
            self.amountMinor = amountMinor
            self.receivableMinor = receivableMinor ?? max(0, amountMinor)
            self.payableMinor = payableMinor ?? max(0, -amountMinor)
            self.groupCount = groupCount
            self.hasOpenBalance = hasOpenBalance
        }
    }

    public let groups: [GroupSlice]

    public init(groups: [GroupSlice]) { self.groups = groups }

    public var currencies: [CurrencyCode] {
        Set(groups.flatMap(\.balances.currencies)).sorted { $0.code < $1.code }
    }

    /// Put the user's actionable currencies first, without comparing amounts across currencies.
    /// Gross debts determine openness: equal debts in separate groups do not settle each other.
    public func summariesForDisplay(userId: UserID) -> [Summary] {
        currencies.map { summary(for: $0, userId: userId) }.sorted {
            if $0.hasOpenBalances != $1.hasOpenBalances { return $0.hasOpenBalances }
            return $0.currency.code < $1.currency.code
        }
    }

    public func summary(for currency: CurrencyCode, userId: UserID) -> Summary {
        var receivable: Int64 = 0
        var payable: Int64 = 0
        for group in groups {
            guard let me = group.members.first(where: { $0.value.linkedUserId == userId })?.key,
                  let balances = group.balances.balances(in: currency) else { continue }
            for transfer in DebtSimplifier.simplify(balances) where transfer.from == me || transfer.to == me {
                if transfer.to == me { receivable += transfer.amountMinor }
                if transfer.from == me { payable += transfer.amountMinor }
            }
        }
        return Summary(currency: currency, receivableMinor: receivable, payableMinor: payable)
    }

    public func people(for currency: CurrencyCode, userId: UserID) -> [Person] {
        var amounts: [String: Int64] = [:]
        var receivables: [String: Int64] = [:]
        var payables: [String: Int64] = [:]
        var open: Set<String> = []
        var counts: [String: Int] = [:]
        var names: [String: String] = [:]
        var memberIds: [String: [MemberID]] = [:]
        for group in groups {
            guard let me = group.members.first(where: { $0.value.linkedUserId == userId })?.key,
                  let balances = group.balances.balances(in: currency) else { continue }
            for transfer in DebtSimplifier.simplify(balances) where transfer.from == me || transfer.to == me {
                let counterpart = transfer.from == me ? transfer.to : transfer.from
                guard let member = group.members[counterpart] else { continue }
                let identity = member.linkedUserId.map { "user:\($0.rawValue.uuidString)" }
                    ?? "member:\(counterpart.rawValue.uuidString)"
                let signedAmount = transfer.to == me ? transfer.amountMinor : -transfer.amountMinor
                amounts[identity, default: 0] += signedAmount
                receivables[identity, default: 0] += max(0, signedAmount)
                payables[identity, default: 0] += max(0, -signedAmount)
                open.insert(identity)
                counts[identity, default: 0] += 1
                names[identity] = names[identity] ?? member.displayName
                memberIds[identity, default: []].append(counterpart)
            }
        }
        return open.compactMap { memberId in
            guard let name = names[memberId] else { return nil }
            let amount = amounts[memberId, default: 0]
            return Person(identity: memberId, memberIds: memberIds[memberId, default: []], name: name, currency: currency,
                          amountMinor: amount, groupCount: counts[memberId, default: 0], hasOpenBalance: true,
                          receivableMinor: receivables[memberId, default: 0], payableMinor: payables[memberId, default: 0])
        }
        .sorted {
            let left = abs($0.amountMinor), right = abs($1.amountMinor)
            if left != right { return left > right }
            let nameOrder = $0.name.localizedStandardCompare($1.name)
            return nameOrder == .orderedSame ? $0.identity < $1.identity : nameOrder == .orderedAscending
        }
    }
}
