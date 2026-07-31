import Foundation
import Testing
@testable import KvittaCore

/// The wall between floating point and money. Rates arrive as decimal strings, become scaled
/// integers, and every conversion is Int64 arithmetic — these tests are what lets the ≈ numbers
/// in the UI be trusted to at least be *deterministically* approximate.
@Suite("Exchange rates")
struct ExchangeRatesTests {

    private var rates: ExchangeRates {
        ExchangeRates(asOf: "2026-07-31", microPerEuro: [
            .sek: 11_234_500,   // "11.2345"
            .dkk: 7_460_300     // "7.4603"
        ])
    }

    @Test("Decimal strings parse by string arithmetic alone", arguments: [
        ("11.2345", 11_234_500 as Int64?),
        ("7.4603", 7_460_300),
        ("0.5", 500_000),
        ("11", 11_000_000),
        ("1.000001", 1_000_001),
        // Beyond six decimals is beyond ECB's own precision: truncated, not rounded.
        ("1.23456789", 1_234_567),
        ("", nil),
        (".", nil),
        ("11,2345", nil),        // decimal comma is display, never wire
        ("-5", nil),             // a negative rate prices nothing
        ("0", nil),              // and a zero rate divides by it
        ("1.2e3", nil),
        ("elva", nil)
    ])
    func parsing(raw: String, expected: Int64?) {
        #expect(ExchangeRates.micro(parsing: raw) == expected)
    }

    @Test("Conversion is integer math with half-away-from-zero rounding")
    func conversionRounds() throws {
        // 100.00 DKK → SEK: 10000 × 11234500 / 7460300 = 15059.046 → rounds down to 15059.
        let dkk = Money(amountMinor: 10_000, currency: .dkk)
        #expect(rates.convert(dkk, to: .sek)?.amountMinor == 15_059)

        // 0.03 DKK → SEK: 3 × 11234500 / 7460300 = 4.518 → rounds up to 5.
        let tiny = Money(amountMinor: 3, currency: .dkk)
        #expect(rates.convert(tiny, to: .sek)?.amountMinor == 5)

        // And the sign mirrors exactly — a debt converts to the same magnitude as a credit.
        #expect(rates.convert(Money(amountMinor: -10_000, currency: .dkk), to: .sek)?.amountMinor == -15_059)
        #expect(rates.convert(Money(amountMinor: -3, currency: .dkk), to: .sek)?.amountMinor == -5)
    }

    @Test("EUR is always present as the identity")
    func euroIdentity() {
        let eur = Money(amountMinor: 5_000, currency: .eur)
        #expect(rates.convert(eur, to: .sek)?.amountMinor == 56_173)  // 50.00 € × 11.2345
        let sek = Money(amountMinor: 11_235, currency: .sek)
        #expect(rates.convert(sek, to: .eur)?.amountMinor == 1_000)   // ≈ 10.00 €
    }

    @Test("Same currency is returned untouched, unknown currency is nil, overflow is nil")
    func edges() {
        let sek = Money(amountMinor: 123, currency: .sek)
        #expect(rates.convert(sek, to: .sek) == sek)

        let isk = Money(amountMinor: 100, currency: CurrencyCode("ISK")!)
        #expect(rates.convert(isk, to: .sek) == nil)

        // A silent wrong number is worse than no number.
        let absurd = Money(amountMinor: .max, currency: .dkk)
        #expect(rates.convert(absurd, to: .sek) == nil)
    }

    @Test("A round trip drifts by at most one öre per leg")
    func roundTripDrift() throws {
        for amount in [1 as Int64, 99, 14_567, 1_000_000] {
            let start = Money(amountMinor: amount, currency: .sek)
            let there = try #require(rates.convert(start, to: .dkk))
            let back = try #require(rates.convert(there, to: .sek))
            #expect(abs(back.amountMinor - amount) <= 1, "\(amount) → \(there.amountMinor) → \(back.amountMinor)")
        }
    }
}
