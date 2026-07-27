import Foundation

/// A deep link that hands a settle-up over to a real payment app.
///
/// The app never moves money (design doc §11) — it prefills someone else's app and then records
/// that the money moved, as a `PaymentRecorded` event. Money goes bank to bank; Kvitta only ever
/// knows about it afterwards.
public struct PaymentLink: Hashable, Sendable {
    /// The URL to open.
    public let url: URL
    /// The scheme to probe with `canOpenURL` before offering it, so a missing app is not a dead end.
    public let probe: URL
    public let method: PaymentMethod

    public init(url: URL, probe: URL, method: PaymentMethod) {
        self.url = url
        self.probe = probe
        self.method = method
    }
}

/// Builds the payment-app links for a settle-up.
///
/// Pure and in Core so it can be tested without a device — which matters more than usual here,
/// because the one thing these tests *cannot* prove is that the receiving app likes the format.
/// That needs a real phone with Swish installed, and until someone runs it there this is
/// unverified against reality.
public enum PaymentLinkBuilder {

    /// Swish, for SEK.
    ///
    /// The documented shape is `swish://payment?data=<url-encoded JSON>&callbackurl=<url>`.
    ///
    /// The amount is built from integer minor units by hand rather than formatted from a
    /// `Double`, because JSON has no decimal type and `43.70` is not representable in binary
    /// floating point. Rendering 437_00 öre through a `Double` is exactly how a settle-up ends up
    /// one öre out — and CLAUDE.md's first rule is that money never touches a float.
    public static func swish(
        payee: String,
        amount: Money,
        message: String,
        callback: URL?
    ) -> PaymentLink? {
        guard amount.currency == .sek, amount.amountMinor > 0 else { return nil }

        let digits = payee.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }

        let json = """
            {"version":1,"payee":{"value":"\(digits)","editable":false},\
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
    public static func preferred(
        for amount: Money,
        payee: String?,
        message: String,
        callback: URL?
    ) -> PaymentLink? {
        switch amount.currency {
        case .sek:
            guard let payee else { return nil }
            return swish(payee: payee, amount: amount, message: message, callback: callback)
        case .dkk:
            return mobilePay(amount: amount)
        default:
            // Cash, or a bank transfer someone arranges themselves. "Markera som betald" is the
            // whole flow, and it always has been for the cash case.
            return nil
        }
    }

    /// Minor units to a JSON decimal, by integer arithmetic only: `43_700` → `"437.00"`.
    static func decimalString(_ minor: Int64) -> String {
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
