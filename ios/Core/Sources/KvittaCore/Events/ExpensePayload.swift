import Foundation

/// A complete expense. `ExpenseUpdated` carries one of these too — a full replacement, never a
/// diff (design doc §2).
///
/// The initialiser throws, and the `Codable` initialiser routes through it, so **an expense that
/// violates `sum(payers) == sum(shares) == amountMinor` cannot exist as a value in this process**.
/// Nothing downstream — projection, balances, simplification — has to check it again, which is
/// why the balances property test can be as blunt as it is.
public struct ExpensePayload: Hashable, Sendable, Codable {
    public let description: String
    public let categoryId: String
    public let date: CalendarDate
    public let currency: CurrencyCode
    public let amountMinor: Int64
    /// Sorted by `memberId`. Every amount is strictly positive.
    public let payers: [MoneyLine]
    /// Sorted by `memberId`. Resolved at creation and never recomputed; zero is allowed.
    public let shares: [MoneyLine]
    /// Display only — which editor mode to reopen. Never used for balance math.
    public let splitMethod: SplitMethod
    /// Display only — what the user typed before rounding resolved it.
    public let splitInput: SplitInput?

    public init(
        description: String,
        categoryId: String,
        date: CalendarDate,
        currency: CurrencyCode,
        amountMinor: Int64,
        payers: [MoneyLine],
        shares: [MoneyLine],
        splitMethod: SplitMethod,
        splitInput: SplitInput? = nil
    ) throws {
        guard amountMinor > 0 else {
            throw CoreError.nonPositiveAmount(field: "amountMinor", value: amountMinor)
        }
        guard !payers.isEmpty else { throw CoreError.emptyLineItems(field: "payers") }
        guard !shares.isEmpty else { throw CoreError.emptyLineItems(field: "shares") }

        try payers.requireUniqueMembers(field: "payers")
        try shares.requireUniqueMembers(field: "shares")

        for line in payers where line.amountMinor <= 0 {
            throw CoreError.nonPositiveAmount(
                field: "payer amount for member \(line.memberId)",
                value: line.amountMinor
            )
        }
        // A share of zero is legitimate: an exact split can leave someone out without removing
        // them from the expense. A negative share is not.
        for line in shares where line.amountMinor < 0 {
            throw CoreError.negativeShare(memberId: line.memberId, value: line.amountMinor)
        }

        let payersTotal = try payers.totalMinor(context: "payers")
        let sharesTotal = try shares.totalMinor(context: "shares")
        guard payersTotal == amountMinor, sharesTotal == amountMinor else {
            throw CoreError.invariantViolated(
                amountMinor: amountMinor,
                payersTotal: payersTotal,
                sharesTotal: sharesTotal
            )
        }

        self.description = description
        self.categoryId = categoryId
        self.date = date
        self.currency = currency
        self.amountMinor = amountMinor
        // Normalised so equality and re-encoding do not depend on the order the wire happened
        // to use.
        self.payers = payers.sortedByMember
        self.shares = shares.sortedByMember
        self.splitMethod = splitMethod
        self.splitInput = splitInput
    }

    /// Builds an expense by resolving `splitInput` into shares.
    ///
    /// This is the path the add-expense screen takes: rounding happens exactly once, here, on the
    /// device that creates the event.
    public static func make(
        description: String,
        categoryId: String,
        date: CalendarDate,
        total: Money,
        payers: [MoneyLine],
        splitInput: SplitInput
    ) throws -> ExpensePayload {
        let shares = try SplitCalculator.resolve(total: total, input: splitInput)
        return try ExpensePayload(
            description: description,
            categoryId: categoryId,
            date: date,
            currency: total.currency,
            amountMinor: total.amountMinor,
            payers: payers,
            shares: shares,
            splitMethod: splitInput.method,
            splitInput: splitInput
        )
    }

    /// Convenience for the overwhelmingly common case: one person paid, split equally.
    public static func make(
        description: String,
        categoryId: String,
        date: CalendarDate,
        total: Money,
        paidBy: MemberID,
        splitEquallyAmong members: [MemberID]
    ) throws -> ExpensePayload {
        try make(
            description: description,
            categoryId: categoryId,
            date: date,
            total: total,
            payers: [MoneyLine(memberId: paidBy, amountMinor: total.amountMinor)],
            splitInput: .equal(among: members)
        )
    }

    public var total: Money {
        Money(amountMinor: amountMinor, currency: currency)
    }

    /// Every member this expense touches, as a payer or a share holder or both.
    public var involvedMembers: Set<MemberID> {
        Set(payers.map(\.memberId)).union(shares.map(\.memberId))
    }

    public func share(of memberId: MemberID) -> Int64 {
        shares.first { $0.memberId == memberId }?.amountMinor ?? 0
    }

    public func paid(by memberId: MemberID) -> Int64 {
        payers.first { $0.memberId == memberId }?.amountMinor ?? 0
    }

    // MARK: - Codable

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            description: container.decodeIfPresent(String.self, forKey: .description) ?? "",
            categoryId: container.decodeIfPresent(String.self, forKey: .categoryId) ?? "",
            date: container.decode(CalendarDate.self, forKey: .date),
            currency: container.decode(CurrencyCode.self, forKey: .currency),
            amountMinor: container.decode(Int64.self, forKey: .amountMinor),
            payers: container.decode([MoneyLine].self, forKey: .payers),
            shares: container.decode([MoneyLine].self, forKey: .shares),
            splitMethod: container.decodeIfPresent(SplitMethod.self, forKey: .splitMethod)
                ?? .exact,
            splitInput: container.decodeIfPresent(SplitInput.self, forKey: .splitInput)
        )
    }
}
