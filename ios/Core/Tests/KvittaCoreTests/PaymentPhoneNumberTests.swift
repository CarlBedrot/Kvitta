import Testing
import Foundation
@testable import KvittaCore

@Suite("Payment phone profiles")
struct PaymentPhoneNumberTests {
    @Test("Swedish legacy and international numbers have one identity", arguments: [
        "070-123 45 67", "701234567", "+46 70 123 45 67", "0046701234567", "46701234567"
    ])
    func swedish(raw: String) {
        let phone = PaymentPhoneNumber(raw)
        #expect(phone?.digits == "46701234567")
        #expect(phone?.country == .sweden)
    }

    @Test("Danish local numbers use the selected country, including numbers starting 45/46", arguments: [
        "20 12 34 56", "45123456", "46123456", "99123456"
    ])
    func danish(raw: String) {
        let phone = PaymentPhoneNumber(raw, country: .denmark)
        #expect(phone?.digits == "45" + raw.filter(\.isNumber))
        #expect(phone?.country == .denmark)
    }

    @Test("International country code overrides the default country")
    func explicitCountry() {
        #expect(PaymentPhoneNumber("+45 20 12 34 56")?.country == .denmark)
        #expect(PaymentPhoneNumber("004520123456")?.digits == "4520123456")
        #expect(PaymentPhoneNumber("4520123456")?.country == .denmark)
        #expect(PaymentPhoneNumber("+46701234567", country: .denmark)?.country == .sweden)
    }

    @Test("Malformed input, foreign countries and merchant aliases are not personal profiles", arguments: [
        "", "+", "12", "++46701234567", "46+701234567", "+46 0701234567",
        "+4720123456", "1233268190", "ring 0701234567", "０７０１２３４５６７",
        "+4510123456", "+45201234567", "+46812345678", "07012345678"
    ])
    func refusesInvalid(raw: String) {
        #expect(PaymentPhoneNumber(raw) == nil)
    }

    @Test("Generated round trips preserve country, exact amount and recipient; never cross currencies")
    func routingProperties() throws {
        for seed in 0..<1000 {
            let swedish = "7" + String(format: "%08d", (seed * 7919) % 100_000_000)
            let danish = String(20_000_000 + (seed * 7919) % 80_000_000)
            for (national, country) in [(swedish, PaymentPhoneNumber.Country.sweden), (danish, .denmark)] {
                let phone = try #require(PaymentPhoneNumber(national, country: country))
                #expect(PaymentPhoneNumber(phone.international) == phone)
                #expect(PaymentPhoneNumber(phone.digits) == phone)
                let minor = Int64(seed + 1) * 7919
                let link = try #require(PaymentLinkBuilder.preferred(
                    for: Money(amountMinor: minor, currency: country.currency), payee: phone.digits, message: "Test"))
                #expect(link.method == country.method)
                if country == .sweden {
                    let components = try #require(URLComponents(url: link.url, resolvingAgainstBaseURL: false))
                    let data = try #require(components.queryItems?.first(where: { $0.name == "data" })?.value)
                    #expect(data.contains("\"value\":\"\(phone.digits)\""))
                    #expect(data.contains("\"value\":\(PaymentLinkBuilder.decimalString(minor))"))
                } else {
                    #expect(link.url.absoluteString == "mobilepay://")
                }
                for currency in [CurrencyCode.sek, .dkk, .eur] where currency != country.currency {
                    #expect(PaymentLinkBuilder.preferred(
                        for: Money(amountMinor: minor, currency: currency), payee: phone.digits, message: "") == nil)
                }
            }
        }
    }

    @Test("A payment requires a recipient and a positive matching-currency amount")
    func prerequisites() {
        for currency in [CurrencyCode.sek, .dkk] {
            #expect(PaymentLinkBuilder.preferred(for: Money(amountMinor: 100, currency: currency), payee: nil, message: "") == nil)
            for minor: Int64 in [0, -1] {
                for phone in ["46701234567", "4520123456"] {
                    #expect(PaymentLinkBuilder.preferred(for: Money(amountMinor: minor, currency: currency), payee: phone, message: "") == nil)
                }
            }
        }
        #expect(PaymentLinkBuilder.mobilePay(amount: Money(amountMinor: 100, currency: .sek)) == nil)
    }
}
