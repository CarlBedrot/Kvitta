import Foundation

/// An amount in integer minor units (öre, øre, cents) plus its currency.
///
/// There is deliberately no way to build one of these from a `Double`, no `FloatingPoint`
/// conformance, and no division operator. Division is not a money operation: splitting an amount
/// between people has a remainder that somebody has to be assigned, which is `Allocator`'s job.
public struct Money: Hashable, Sendable, Codable, CustomStringConvertible {
    public let amountMinor: Int64
    public let currency: CurrencyCode

    public init(amountMinor: Int64, currency: CurrencyCode) {
        self.amountMinor = amountMinor
        self.currency = currency
    }

    public static func zero(_ currency: CurrencyCode) -> Money {
        Money(amountMinor: 0, currency: currency)
    }

    public var isZero: Bool { amountMinor == 0 }
    public var isPositive: Bool { amountMinor > 0 }
    public var isNegative: Bool { amountMinor < 0 }
    public var magnitude: Money { Money(amountMinor: Swift.abs(amountMinor), currency: currency) }

    public var description: String { "\(amountMinor) \(currency) (minor units)" }

    // MARK: - Arithmetic

    // Mixing currencies is a bug in the calling code, not bad input data — the group's currency
    // is fixed and every amount in it is validated on the way in. So these trap rather than throw:
    // a mismatch here means a wrong branch was taken, and failing loudly beats a plausible number.

    public static func + (lhs: Money, rhs: Money) -> Money {
        Money(amountMinor: lhs.amountMinor + rhs.requiring(lhs.currency), currency: lhs.currency)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        Money(amountMinor: lhs.amountMinor - rhs.requiring(lhs.currency), currency: lhs.currency)
    }

    public static func * (lhs: Money, rhs: Int64) -> Money {
        Money(amountMinor: lhs.amountMinor * rhs, currency: lhs.currency)
    }

    public static prefix func - (value: Money) -> Money {
        Money(amountMinor: -value.amountMinor, currency: value.currency)
    }

    public static func += (lhs: inout Money, rhs: Money) { lhs = lhs + rhs }
    public static func -= (lhs: inout Money, rhs: Money) { lhs = lhs - rhs }

    private func requiring(_ expected: CurrencyCode) -> Int64 {
        precondition(
            currency == expected,
            "Cannot combine \(currency) with \(expected). Amounts in one group share one currency."
        )
        return amountMinor
    }

    /// Sums amounts that are already known to share a currency, throwing instead of trapping on
    /// overflow. Used on decode paths where the input is not yet trusted.
    static func sum(_ amounts: [Int64], context: String) throws -> Int64 {
        var total: Int64 = 0
        for amount in amounts {
            let (next, overflowed) = total.addingReportingOverflow(amount)
            guard !overflowed else { throw CoreError.amountOverflow(context: context) }
            total = next
        }
        return total
    }
}

extension Money: Comparable {
    public static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(
            lhs.currency == rhs.currency,
            "Cannot compare \(lhs.currency) with \(rhs.currency)."
        )
        return lhs.amountMinor < rhs.amountMinor
    }
}
