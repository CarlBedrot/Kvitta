import Foundation
import KvittaCore

/// The text behind "Påminn" (README §6.4): a ready-to-send nudge naming the amount, the group,
/// and where to pay — "Hej! Du är skyldig mig 676,55 kr i Vårt äktenskap. Swisha gärna till
/// 070-123 45 67 🙂". A pure function, not a view, so every "Påminn" entry point — the group
/// footer, a pair in STÄLLNING's utfällning — builds the exact same sentence and so it is
/// testable without a device.
///
/// `myNumber` is the sender's *own* payment number (`UserProfile.paymentPhone`), never
/// `PayeeDirectory`'s: a reminder tells the debtor where to send money *to*, which is always the
/// reminder's author, not the person being reminded.
enum ReminderMessage {

    static func text(amountMinor: Int64, currency: CurrencyCode, groupName: String, myNumber: PaymentPhoneNumber?) -> String {
        let amount = StevenMoneyFormat.string(amountMinor, currency, explicit: false)
        guard let myNumber else {
            return String(localized: "Hej! Du är skyldig mig \(amount) i \(groupName). 🙂")
        }
        switch myNumber.country {
        case .sweden:
            return String(localized: "Hej! Du är skyldig mig \(amount) i \(groupName). Swisha gärna till \(myNumber.international) 🙂")
        case .denmark:
            return String(localized: "Hej! Du är skyldig mig \(amount) i \(groupName). Betala gärna via MobilePay till \(myNumber.international) 🙂")
        }
    }
}
