import Foundation
import Testing
import KvittaCoreTestSupport
@testable import KvittaCore

/// Handing a settle-up to Swish or MobilePay.
///
/// Worth saying plainly what these can and cannot prove. They pin the amount arithmetic, the
/// number normalisation, the escaping, and which currencies get which button — all of which are
/// ours to get right. They cannot prove Swish accepts the payload, because that needs a real
/// phone with Swish on it. One such phone has already rejected the `swish://payment?data=` shape;
/// the universal link below is the replacement and is itself unverified until someone taps it.
@Suite("Payment links")
struct PaymentLinkTests {
    private let callback = URL(string: "kvitta://payment-return")!

    private func query(_ link: PaymentLink) throws -> [String: String] {
        let components = try #require(URLComponents(url: link.url, resolvingAgainstBaseURL: false))
        let items = try #require(components.queryItems)
        return Dictionary(items.compactMap { item in item.value.map { (item.name, $0) } }) { _, last in last }
    }

    private func appSwitchData(in link: PaymentLink) throws -> String {
        try #require(query(link)["data"])
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

    // MARK: - The payee

    @Test("However you write a Swedish number, Swish gets country code plus number", arguments: [
        ("070-123 45 67", "46701234567"),
        ("0701234567", "46701234567"),
        ("+46 70 123 45 67", "46701234567"),
        ("46701234567", "46701234567"),
        ("0046701234567", "46701234567"),
        // The trunk zero already dropped. No merchant number starts with 7, so this is safe.
        ("701234567", "46701234567"),
        // A merchant number is not a phone number and must not collect a country code.
        ("123 326 81 90", "1233268190")
    ])
    func numbersAreNormalised(raw: String, expected: String) {
        #expect(SwishNumber.normalised(raw) == expected)
    }

    @Test("Nothing that could not be a number gets sent as one", arguments: [
        "ring mig",
        "",
        "12",
        "1234567890123456789"
    ])
    func nonsenseIsRefused(raw: String) {
        #expect(SwishNumber.normalised(raw) == nil)
    }

    // MARK: - The link we lead with

    @Test("The Swish link carries the payee, the exact amount and the message")
    func swishCarriesEverything() throws {
        let link = try #require(PaymentLinkBuilder.swish(
            payee: "070-123 45 67",
            amount: Money(amountMinor: 14_567, currency: .sek),
            message: "Fjällresan"
        ))

        // Asserted on the whole prefix rather than on `url.path`, which normalises the trailing
        // slash away — and the trailing slash is part of the path Swish serves.
        #expect(link.url.absoluteString.hasPrefix("https://app.swish.nu/1/p/sw/?"))

        let items = try query(link)
        #expect(items["sw"] == "46701234567")
        #expect(items["amt"] == "145.67")
        #expect(items["cur"] == "SEK")
        #expect(items["msg"] == "Fjällresan")
        // The payer may reword the message; the amount is not theirs to change.
        #expect(items["edit"] == "msg")

        #expect(link.method == .swish)
        // https cannot be probed with canOpenURL, and pretending otherwise would gate the button
        // on an answer that is always yes.
        #expect(link.probe == nil)
        // No callback: coming back is read from the scene phase, and the callback is what made
        // Swish ask "open Kvitta?" on the way out.
        #expect(items["callbackurl"] == nil)
    }

    @Test("Swish is refused for anything that is not a positive SEK amount")
    func swishRefusesNonsense() {
        #expect(PaymentLinkBuilder.swish(
            payee: "0701234567",
            amount: Money(amountMinor: 100, currency: .dkk),
            message: "") == nil)

        #expect(PaymentLinkBuilder.swish(
            payee: "0701234567",
            amount: Money(amountMinor: 0, currency: .sek),
            message: "") == nil)

        #expect(PaymentLinkBuilder.swish(
            payee: "ring mig",
            amount: Money(amountMinor: 100, currency: .sek),
            message: "") == nil)
    }

    // MARK: - The alternate shape, kept as a candidate

    @Test("The app-switch payload still normalises the number and stays valid JSON")
    func appSwitchIsWellFormed() throws {
        let link = try #require(PaymentLinkBuilder.swishAppSwitch(
            payee: "070-123 45 67",
            amount: Money(amountMinor: 14_567, currency: .sek),
            message: "he said \"hi\"",
            callback: callback
        ))

        let payload = try appSwitchData(in: link)
        #expect(payload.contains("\"value\":\"46701234567\""))
        #expect(payload.contains("\"value\":145.67"))
        #expect(payload.contains("\\\"hi\\\""))
        #expect(link.url.absoluteString.contains("callbackurl"))
        #expect(link.probe?.scheme == "swish")

        // The proof a quote in the message is still one well-formed object, not two.
        let parsed = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        #expect(parsed != nil)
    }

    // MARK: - Which button appears

    @Test("Each currency gets the button that exists for it")
    func preferredByCurrency() throws {
        let sek = PaymentLinkBuilder.preferred(
            for: Money(amountMinor: 100, currency: .sek),
            payee: "0701234567", message: "")
        #expect(sek?.method == .swish)
        #expect(sek?.url.host == "app.swish.nu")

        // MobilePay has no public prefill link, so this only opens the app — inventing a format
        // would give us a button that quietly does the wrong thing.
        let dkk = PaymentLinkBuilder.preferred(
            for: Money(amountMinor: 100, currency: .dkk),
            payee: nil, message: "")
        #expect(dkk?.method == .mobilePay)

        // No payee, no link: falling back to "mark as paid" is correct, not a failure.
        #expect(PaymentLinkBuilder.preferred(
            for: Money(amountMinor: 100, currency: .sek),
            payee: nil, message: "") == nil)

        // A currency neither app handles. Cash has always been the whole flow here.
        #expect(PaymentLinkBuilder.preferred(
            for: Money(amountMinor: 100, currency: .eur),
            payee: "0701234567", message: "") == nil)
    }
}
