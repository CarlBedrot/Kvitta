import Testing
import KvittaCore
@testable import Kvitta

struct ReminderMessageTests {
    private let swedishNumber = PaymentPhoneNumber("0701234567")!
    private let danishNumber = PaymentPhoneNumber("20123456", country: .denmark)!

    @Test func swedishNumberOffersSwish() {
        let text = ReminderMessage.text(amountMinor: 67_655, currency: .sek, groupName: "Vårt äktenskap", myNumber: swedishNumber)
        #expect(text.contains("676,55"))
        #expect(text.contains("Vårt äktenskap"))
        #expect(text.contains("Swisha"))
        #expect(text.contains(swedishNumber.international))
    }

    @Test func danishNumberOffersMobilePay() {
        let text = ReminderMessage.text(amountMinor: 10_000, currency: .dkk, groupName: "Köpenhamn", myNumber: danishNumber)
        #expect(text.contains("MobilePay"))
        #expect(text.contains(danishNumber.international))
        #expect(!text.contains("Swish"))
    }

    @Test func noNumberDropsThePaymentInstructionRatherThanCrashing() {
        let text = ReminderMessage.text(amountMinor: 1_000, currency: .sek, groupName: "Resan", myNumber: nil)
        #expect(text.contains("Resan"))
        #expect(!text.contains("Swish"))
        #expect(!text.contains("MobilePay"))
    }

    @Test func wholeKronorOmitsTheDecimals() {
        let text = ReminderMessage.text(amountMinor: 10_000, currency: .sek, groupName: "Resan", myNumber: swedishNumber)
        #expect(text.contains("100\u{00A0}kr"))
    }
}
