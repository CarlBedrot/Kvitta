import Foundation

/// ECB reference rates, held as scaled integers, for display-only conversion.
///
/// Two rules meet here and both survive:
///
/// - **Money never touches a float.** ECB publishes rates as decimal *strings* ("11.2345"); they
///   are parsed by string and integer arithmetic into micro-units per euro (`11_234_500`) and
///   every conversion is `Int64` math. A `Double` never sits between a rate and an amount.
/// - **The ledger stores only what happened.** Nothing converted is ever written to an event.
///   A converted amount is an *approximation for a viewer*, marked ≈ in the UI, and it changes
///   when the rate does — which is exactly why it can never be the stored truth.
public struct ExchangeRates: Hashable, Sendable, Codable {
    /// ECB's own date for the fixing, e.g. "2026-07-31". Display only.
    public let asOf: String
    /// Micro-units of each currency per one euro: 11.2345 SEK/EUR → `11_234_500`.
    public let microPerEuro: [CurrencyCode: Int64]

    public static let microScale: Int64 = 1_000_000

    public init(asOf: String, microPerEuro: [CurrencyCode: Int64]) {
        self.asOf = asOf
        var rates = microPerEuro
        // The euro is the base and always present, so EUR→EUR and EUR-leg conversions need no
        // special case anywhere else.
        rates[.eur] = Self.microScale
        self.microPerEuro = rates.filter { $0.value > 0 }
    }

    /// The currencies this table can convert between.
    public var currencies: [CurrencyCode] {
        microPerEuro.keys.sorted { $0.code < $1.code }
    }

    /// Converts through the euro: `amount × micro(to) / micro(from)`, rounded half away from
    /// zero, deterministically. `nil` when either currency is missing from the table or the
    /// arithmetic would overflow — a silent wrong number is worse than no number.
    public func convert(_ money: Money, to target: CurrencyCode) -> Money? {
        if money.currency == target { return money }
        guard let fromMicro = microPerEuro[money.currency],
              let toMicro = microPerEuro[target] else { return nil }

        // amount × toMicro first, then divide — the other order loses everything below the
        // rate's own precision. Overflow-checked because amount is user data.
        let (product, overflow) = money.amountMinor.multipliedReportingOverflow(by: toMicro)
        guard !overflow else { return nil }

        let quotient = product / fromMicro
        let remainder = product % fromMicro
        // Round half away from zero: |remainder| doubled reaching the divisor rounds out.
        let roundsOut = remainder.magnitude * 2 >= fromMicro.magnitude
        let rounded = quotient + (roundsOut ? (product < 0 ? -1 : 1) : 0)

        return Money(amountMinor: rounded, currency: target)
    }

    /// `"11.2345"` → `11_234_500`. Pure string and integer arithmetic — this is the wall that
    /// keeps floating point away from the whole feature. Accepts an optional fraction of any
    /// length (truncating beyond six digits, which is beyond ECB's own precision); rejects
    /// anything that is not a plain positive decimal.
    public static func micro(parsing decimal: String) -> Int64? {
        let parts = decimal.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }

        let wholePart = parts[0]
        guard !wholePart.isEmpty, wholePart.allSatisfy(\.isASCII),
              let whole = Int64(wholePart), whole >= 0 else { return nil }

        var fractionMicro: Int64 = 0
        if parts.count == 2 {
            let fraction = String(parts[1].prefix(6))
            guard !fraction.isEmpty, fraction.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let digits = Int64(fraction) else { return nil }
            // "2345" are the first four of six micro digits: pad the rest with zeros.
            var scaled = digits
            for _ in fraction.count..<6 { scaled *= 10 }
            fractionMicro = scaled
        }

        let (wholeMicro, overflow) = whole.multipliedReportingOverflow(by: microScale)
        guard !overflow else { return nil }
        let total = wholeMicro + fractionMicro
        return total > 0 ? total : nil
    }
}
