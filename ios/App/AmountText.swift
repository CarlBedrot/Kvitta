import SwiftUI
import KvittaCore

/// Formats money for display. **Integer arithmetic only** — no `Double` ever touches an amount,
/// on the way in or the way out (CLAUDE.md). Mirrors the öre handling the diagnostics view used.
enum MoneyFormat {
    /// How the leading sign is shown.
    enum SignStyle {
        /// Magnitude only: `"437 kr"`. For expense totals and shares.
        case none
        /// A leading minus when negative: `"-152 kr"`.
        case negativeOnly
        /// A leading `+` or `-`, but bare `"0 kr"` at zero. For balances (matches the mockup).
        case always
    }

    /// The user-facing currency symbol. The Nordic krona currencies all read "kr".
    static func symbol(_ currency: CurrencyCode) -> String {
        switch currency {
        case .sek, .dkk, .nok: return "kr"
        case .eur: return "€"
        default: return currency.code
        }
    }

    /// `43_700` SEK → `"437 kr"`; `14_566` → `"145,66 kr"`. Swedish decimal comma.
    static func string(_ amountMinor: Int64, _ currency: CurrencyCode, sign: SignStyle = .none) -> String {
        let magnitude = abs(amountMinor)
        let kronor = magnitude / 100
        let ore = magnitude % 100
        // Öre only when there is a remainder — the mockup writes whole amounts as "437 kr".
        let number = ore == 0 ? "\(kronor)" : "\(kronor),\(ore < 10 ? "0" : "")\(ore)"
        return "\(prefix(amountMinor, sign))\(number) \(symbol(currency))"
    }

    private static func prefix(_ amountMinor: Int64, _ sign: SignStyle) -> String {
        switch sign {
        case .none: return ""
        case .negativeOnly: return amountMinor < 0 ? "-" : ""
        case .always:
            if amountMinor > 0 { return "+" }
            if amountMinor < 0 { return "-" }
            return ""
        }
    }
}

/// An amount rendered the way the design demands everywhere: SF Rounded, monospaced digits,
/// semibold, coloured by sign. The loudest thing on any screen.
///
/// Colour never carries meaning alone (accessibility floor) — callers pair this with a direction
/// word, and the VoiceOver label folds direction, amount, and counterpart into one phrase.
struct SignedAmountText: View {
    let amountMinor: Int64
    let currency: CurrencyCode
    var size: CGFloat = 17
    var sign: MoneyFormat.SignStyle = .always
    /// A spoken phrase for VoiceOver, e.g. "Du ska få 340 kronor". Falls back to the plain string.
    var accessibilityPhrase: String?

    var body: some View {
        Text(MoneyFormat.string(amountMinor, currency, sign: sign))
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.tint(forSign: amountMinor))
            .accessibilityLabel(accessibilityPhrase ?? MoneyFormat.string(amountMinor, currency, sign: sign))
    }
}

/// Which way a balance leans, with the Swedish word the UI must show next to the number so colour
/// is never the only signal. Keys are the reference (Swedish) copy; the String Catalog holds `en`.
enum BalanceDirection {
    case owed      // positive — the group owes you
    case owe       // negative — you owe the group
    case settled   // zero

    init(_ amountMinor: Int64) {
        if amountMinor > 0 { self = .owed }
        else if amountMinor < 0 { self = .owe }
        else { self = .settled }
    }

    /// A short label shown beside a balance ("du ska få" / "du är skyldig" / "kvitt").
    var word: LocalizedStringKey {
        switch self {
        case .owed: return "du ska få"
        case .owe: return "du är skyldig"
        case .settled: return "kvitt"
        }
    }

    /// The same word as a resolved string, for composing VoiceOver phrases.
    var spokenWord: String {
        switch self {
        case .owed: return String(localized: "du ska få")
        case .owe: return String(localized: "du är skyldig")
        case .settled: return String(localized: "kvitt")
        }
    }
}
