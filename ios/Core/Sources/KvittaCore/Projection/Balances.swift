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

/// Every balance in a group, one `Balances` per currency — the shape of a group since M7.
///
/// A group is a container of per-currency sub-ledgers: an expense is always in exactly one
/// currency (its rounding invariant depends on that), but a trip can hold ICA receipts in SEK
/// and restaurant bills in DKK side by side. Nothing here converts anything — conversion is a
/// display concern (`ExchangeRates`), and a stored conversion would break the zero-sum property
/// the moment a rate moved.
public struct GroupBalances: Hashable, Sendable {
    /// Sorted by currency code, so two devices with the same log render the same order.
    public let byCurrency: [Balances]

    public init(byCurrency: [Balances]) {
        self.byCurrency = byCurrency.sorted { $0.currency.code < $1.currency.code }
    }

    public func balances(in currency: CurrencyCode) -> Balances? {
        byCurrency.first { $0.currency == currency }
    }

    /// One member's position in every currency they have any position in. Zero-balances in a
    /// currency the member never touched are omitted; a zero in a currency they moved through
    /// is kept, because "kvitt" is information.
    public func money(for memberId: MemberID) -> [Money] {
        byCurrency.map { $0.money(for: memberId) }
    }

    /// Settled means *every* bucket is settled. One outstanding DKK debt keeps a group open no
    /// matter how clean the SEK side is.
    public var isSettled: Bool {
        byCurrency.allSatisfy(\.isSettled)
    }

    public var currencies: [CurrencyCode] {
        byCurrency.map(\.currency)
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
