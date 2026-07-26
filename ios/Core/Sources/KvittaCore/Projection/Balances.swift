import Foundation

/// Net position per member in one group, in minor units.
///
/// Positive means the group owes you; negative means you owe the group. `total` is always exactly
/// zero, and property test P1 is the reason to believe that.
public struct Balances: Hashable, Sendable {
    public let currency: CurrencyCode
    public let byMember: [MemberID: Int64]

    public init(currency: CurrencyCode, byMember: [MemberID: Int64]) {
        self.currency = currency
        self.byMember = byMember
    }

    public func amountMinor(for memberId: MemberID) -> Int64 {
        byMember[memberId] ?? 0
    }

    public func money(for memberId: MemberID) -> Money {
        Money(amountMinor: amountMinor(for: memberId), currency: currency)
    }

    /// Zero for any valid group. If this is ever non-zero, money has been invented or destroyed.
    public var totalMinor: Int64 {
        byMember.values.reduce(0, +)
    }

    public var isSettled: Bool {
        byMember.values.allSatisfy { $0 == 0 }
    }

    /// Members owed money, largest first, ties broken on `memberId` so the order is reproducible.
    public var creditors: [(memberId: MemberID, amountMinor: Int64)] {
        sortedEntries(where: { $0 > 0 }, descendingByMagnitude: true)
    }

    /// Members who owe money, largest debt first. Amounts are the negative balances as stored.
    public var debtors: [(memberId: MemberID, amountMinor: Int64)] {
        sortedEntries(where: { $0 < 0 }, descendingByMagnitude: true)
    }

    private func sortedEntries(
        where include: (Int64) -> Bool,
        descendingByMagnitude: Bool
    ) -> [(memberId: MemberID, amountMinor: Int64)] {
        byMember
            .filter { include($0.value) }
            .map { (memberId: $0.key, amountMinor: $0.value) }
            .sorted { left, right in
                let leftMagnitude = abs(left.amountMinor)
                let rightMagnitude = abs(right.amountMinor)
                if leftMagnitude != rightMagnitude {
                    return descendingByMagnitude
                        ? leftMagnitude > rightMagnitude
                        : leftMagnitude < rightMagnitude
                }
                return left.memberId < right.memberId
            }
    }
}

/// One line behind a balance: which expense or payment moved it, and by how much.
///
/// This is what makes a balance auditable rather than a number you have to trust. Tapping a
/// balance shows these in order, with `runningTotalMinor` landing on exactly the number tapped.
public struct LedgerEntry: Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        case expense(ExpenseID)
        case payment(PaymentID)
    }

    public let source: Source
    public let date: CalendarDate
    public let title: String
    public let memberId: MemberID
    /// What this line did to the member's balance. Positive means they moved toward being owed.
    public let deltaMinor: Int64
    public let runningTotalMinor: Int64

    public init(
        source: Source,
        date: CalendarDate,
        title: String,
        memberId: MemberID,
        deltaMinor: Int64,
        runningTotalMinor: Int64
    ) {
        self.source = source
        self.date = date
        self.title = title
        self.memberId = memberId
        self.deltaMinor = deltaMinor
        self.runningTotalMinor = runningTotalMinor
    }
}
