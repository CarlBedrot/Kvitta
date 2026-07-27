import Foundation
import Testing
import KvittaCoreTestSupport
@testable import KvittaCore

/// Handing a settle-up to Swish or MobilePay.
///
/// Worth saying plainly what these can and cannot prove. They pin the amount arithmetic, the
/// escaping, and which currencies get which button — all of which are ours to get right. They
/// cannot prove Swish accepts the payload, because that needs a real phone with Swish on it. The
/// format is unverified against reality until someone runs it there.
@Suite("Payment links")
struct PaymentLinkTests {
    private let callback = URL(string: "kvitta://payment-return")!

    private func data(in link: PaymentLink) throws -> String {
        let components = try #require(URLComponents(url: link.url, resolvingAgainstBaseURL: false))
        return try #require(components.queryItems?.first { $0.name == "data" }?.value)
    }

    @Test("Öre become a decimal without ever touching a float", arguments: [
        (43_700 as Int64, "437.00"),
        (14_567, "145.67"),
        (5, "0.05"),
        (99, "0.99"),
        (100, "1.00"),
        (1_000_000_00, "1000000.00")
    ])
    func decimalsAreExact(minor: Int64, expected: String) {
        // 437.00 is not representable in binary floating point. Formatting money through a Double
        // is how a settle-up ends up an öre out, and CLAUDE.md's first rule forbids it.
        #expect(PaymentLinkBuilder.decimalString(minor) == expected)
    }

    @Test("A Swish link carries the payee, the exact amount and the message")
    func swishCarriesEverything() throws {
        let link = try #require(PaymentLinkBuilder.swish(
            payee: "070-123 45 67",
            amount: Money(amountMinor: 14_567, currency: .sek),
            message: "Fjällresan",
            callback: callback
        ))

        let payload = try data(in: link)
        // Punctuation people type into a phone number must not reach the payload.
        #expect(payload.contains("\"value\":\"0701234567\""))
        #expect(payload.contains("\"value\":145.67"))
        #expect(payload.contains("Fjällresan"))
        #expect(link.method == .swish)
        #expect(link.url.absoluteString.contains("callbackurl"))
    }

    @Test("A quote in the message cannot break out of the JSON")
    func messageIsEscaped() throws {
        let link = try #require(PaymentLinkBuilder.swish(
            payee: "0701234567",
            amount: Money(amountMinor: 100, currency: .sek),
            message: "he said \"hi\"",
            callback: nil
        ))

        let payload = try data(in: link)
        #expect(payload.contains("\\\"hi\\\""))
        // The proof it is still one well-formed object, not two.
        let parsed = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        #expect(parsed != nil)
    }

    @Test("Swish is refused for anything that is not a positive SEK amount")
    func swishRefusesNonsense() {
        #expect(PaymentLinkBuilder.swish(
            payee: "0701234567",
            amount: Money(amountMinor: 100, currency: .dkk),
            message: "", callback: nil) == nil)

        #expect(PaymentLinkBuilder.swish(
            payee: "0701234567",
            amount: Money(amountMinor: 0, currency: .sek),
            message: "", callback: nil) == nil)

        // A "phone number" with no digits in it.
        #expect(PaymentLinkBuilder.swish(
            payee: "ring mig",
            amount: Money(amountMinor: 100, currency: .sek),
            message: "", callback: nil) == nil)
    }

    @Test("Each currency gets the button that exists for it")
    func preferredByCurrency() throws {
        let sek = PaymentLinkBuilder.preferred(
            for: Money(amountMinor: 100, currency: .sek),
            payee: "0701234567", message: "", callback: nil)
        #expect(sek?.method == .swish)

        // MobilePay has no public prefill link, so this only opens the app — inventing a format
        // would give us a button that quietly does the wrong thing.
        let dkk = PaymentLinkBuilder.preferred(
            for: Money(amountMinor: 100, currency: .dkk),
            payee: nil, message: "", callback: nil)
        #expect(dkk?.method == .mobilePay)

        // No payee, no link: falling back to "mark as paid" is correct, not a failure.
        #expect(PaymentLinkBuilder.preferred(
            for: Money(amountMinor: 100, currency: .sek),
            payee: nil, message: "", callback: nil) == nil)

        // A currency neither app handles. Cash has always been the whole flow here.
        #expect(PaymentLinkBuilder.preferred(
            for: Money(amountMinor: 100, currency: .eur),
            payee: "0701234567", message: "", callback: nil) == nil)
    }
}
