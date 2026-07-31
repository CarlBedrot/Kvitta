import Foundation

/// A deep link that hands a settle-up over to a real payment app.
///
/// The app never moves money (design doc §11) — it prefills someone else's app and then records
/// that the money moved, as a `PaymentRecorded` event. Money goes bank to bank; Kvitta only ever
/// knows about it afterwards.
public struct PaymentLink: Hashable, Sendable {
    /// The URL to open.
    public let url: URL
    /// A custom scheme to probe with `canOpenURL` before offering the link, when there is one.
    ///
    /// `nil` for an https universal link, which cannot be probed: `canOpenURL` on https always
    /// answers yes (Safari can open it) and says nothing about whether the app claims it. That is
    /// fine — `openURL`'s completion is the check that actually matters, and an https link that
    /// falls through to the web lands on a page offering the download rather than dead-ending.
    public let probe: URL?
    public let method: PaymentMethod

    public init(url: URL, probe: URL?, method: PaymentMethod) {
        self.url = url
        self.probe = probe
        self.method = method
    }
}

/// A Swish payee, in the form Swish expects.
///
/// Swish's API documents the payee as country code plus number — `46701234567`, not `0701234567`.
/// The first version of this file passed on whatever digits somebody typed, which is the most
/// likely reason a real phone answered *"länken som användes för att öppna appen har ett felaktigt
/// format"*.
public enum SwishNumber {

    /// `"070-123 45 67"` → `"46701234567"`, or `nil` if there is no plausible number in there.
    ///
    /// Merchant numbers (ten digits beginning `123`) are deliberately passed through untouched:
    /// they are not phone numbers and must not collect a country code.
    public static func normalised(_ raw: String) -> String? {
        var digits = String(raw.filter(\.isNumber))

        if digits.hasPrefix("00") {
            // 0046… — the international prefix, written out.
            digits.removeFirst(2)
        } else if digits.hasPrefix("0") {
            // 070… — the Swedish national form, which is how anyone actually writes it down.
            digits = "46" + digits.dropFirst()
        } else if digits.hasPrefix("7") && digits.count == 9 {
            // 70123456 7 — a mobile number with the trunk zero already dropped. Unambiguous
            // because no merchant number starts with 7.
            digits = "46" + digits
        }

        // Swish's own bound on an alias. Below it there is no number; above it there is no point.
        guard (8...15).contains(digits.count) else { return nil }
        return digits
    }
}

/// Builds the payment-app links for a settle-up.
///
/// Pure and in Core so it can be tested without a device — which matters more than usual here,
/// because the one thing these tests *cannot* prove is that the receiving app likes the format.
/// That needs a real phone with Swish installed.
public enum PaymentLinkBuilder {

    /// Swish, for SEK. The link Swish's own site hands out for a prefilled payment:
    ///
    ///     https://app.swish.nu/1/p/sw/?sw=46701234567&amt=145.67&cur=SEK&msg=Fjällresan&edit=msg
    ///
    /// `edit=msg` names the fields the payer may change — so the message is theirs to adjust and
    /// the amount is not, which is the same intent the old app-switch payload spelled out at
    /// length.
    ///
    /// There is deliberately no callback URL. Coming back is already detected from the scene
    /// phase, and the callback is what made Swish ask *"open Kvitta?"* on the way out — a prompt
    /// that reads like the app wants something when all it wants is to ask whether you paid.
    ///
    /// The amount is built from integer minor units by hand rather than formatted from a
    /// `Double`, because `43.70` is not representable in binary floating point. Rendering
    /// 437_00 öre through a `Double` is exactly how a settle-up ends up one öre out — and
    /// CLAUDE.md's first rule is that money never touches a float.
    public static func swish(payee: String, amount: Money, message: String) -> PaymentLink? {
        guard amount.currency == .sek, amount.amountMinor > 0,
              let number = SwishNumber.normalised(payee) else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "app.swish.nu"
        components.path = "/1/p/sw/"
        components.queryItems = [
            URLQueryItem(name: "sw", value: number),
            URLQueryItem(name: "amt", value: decimalString(amount.amountMinor)),
            URLQueryItem(name: "cur", value: amount.currency.code),
            URLQueryItem(name: "msg", value: message),
            URLQueryItem(name: "edit", value: "msg")
        ]

        guard let url = components.url else { return nil }
        return PaymentLink(url: url, probe: nil, method: .swish)
    }

    /// The other Swish shape: `swish://payment?data=<url-encoded JSON>`.
    ///
    /// Undocumented, and rejected by the Swish app on the one real phone it has been tried on.
    /// Kept rather than deleted because it is the only alternative to `swish(payee:amount:message:)`
    /// if that one also turns out to be wrong, and because the debug format tester offers both —
    /// throwing it away would mean guessing again from nothing.
    public static func swishAppSwitch(
        payee: String,
        amount: Money,
        message: String,
        callback: URL?
    ) -> PaymentLink? {
        guard amount.currency == .sek, amount.amountMinor > 0,
              let number = SwishNumber.normalised(payee) else { return nil }

        let json = """
            {"version":1,"payee":{"value":"\(number)","editable":false},\
            "amount":{"value":\(decimalString(amount.amountMinor)),"editable":false},\
            "message":{"value":"\(escape(message))","editable":true}}
            """

        var components = URLComponents()
        components.scheme = "swish"
        components.host = "payment"
        components.queryItems = [
            URLQueryItem(name: "data", value: json),
            callback.map { URLQueryItem(name: "callbackurl", value: $0.absoluteString) }
        ].compactMap { $0 }

        guard let url = components.url, let probe = URL(string: "swish://") else { return nil }
        return PaymentLink(url: url, probe: probe, method: .swish)
    }

    /// MobilePay, for DKK.
    ///
    /// Deliberately just opens the app. MobilePay has no public person-to-person prefill link, and
    /// inventing one would produce a button that silently does the wrong thing. The UI pairs this
    /// with the amount on the clipboard, which is honest about what it can and cannot do.
    public static func mobilePay(amount: Money) -> PaymentLink? {
        guard amount.amountMinor > 0,
              let url = URL(string: "mobilepay://") else { return nil }

        return PaymentLink(url: url, probe: url, method: .mobilePay)
    }

    /// The link worth offering for this currency, if any.
    public static func preferred(for amount: Money, payee: String?, message: String) -> PaymentLink? {
        switch amount.currency {
        case .sek:
            guard let payee else { return nil }
            return swish(payee: payee, amount: amount, message: message)
        case .dkk:
            return mobilePay(amount: amount)
        default:
            // Cash, or a bank transfer someone arranges themselves. "Markera som betald" is the
            // whole flow, and it always has been for the cash case.
            return nil
        }
    }

    /// Minor units to a decimal, by integer arithmetic only: `43_700` → `"437.00"`.
    /// Public since M7: the MobilePay clipboard hand-off needs the same exact string.
    public static func decimalString(_ minor: Int64) -> String {
        let major = minor / 100
        let remainder = abs(minor % 100)
        return "\(major).\(remainder < 10 ? "0" : "")\(remainder)"
    }

    /// JSON string escaping, for the message a person typed.
    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
