import Foundation

/// A personal payment number, distinct from Swish merchant aliases. Validation checks shape,
/// not ownership or whether the number is registered with the payment provider.
public struct PaymentPhoneNumber: Equatable, Sendable {
    public enum Country: String, CaseIterable, Sendable {
        case sweden = "46"
        case denmark = "45"

        public var method: PaymentMethod { self == .sweden ? .swish : .mobilePay }
        public var currency: CurrencyCode { self == .sweden ? .sek : .dkk }
    }

    public let country: Country
    /// International digits without +, matching the existing mutable profile wire format.
    public let digits: String
    public var international: String { "+" + digits }

    public init?(_ raw: String, country defaultCountry: Country = .sweden) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.allSatisfy({ "0123456789+ -().".contains($0) }),
              value.filter({ $0 == "+" }).count <= 1,
              !value.contains("+") || value.hasPrefix("+") else { return nil }
        var number = String(value.filter { "0123456789".contains($0) })
        let explicit = value.hasPrefix("+") || number.hasPrefix("00")
        if number.hasPrefix("00") { number.removeFirst(2) }

        let region: Country
        if explicit || (number.hasPrefix("46") && number.count == 11)
            || (number.hasPrefix("45") && number.count == 10) {
            guard let found = Country(rawValue: String(number.prefix(2))) else { return nil }
            region = found
            number.removeFirst(2)
        } else {
            region = defaultCountry
            if region == .sweden && number.hasPrefix("0") { number.removeFirst() }
        }
        switch region {
        case .sweden:
            guard number.count == 9, number.hasPrefix("7") else { return nil }
        case .denmark:
            guard number.count == 8, let first = number.first, "23456789".contains(first) else { return nil }
        }
        country = region
        digits = region.rawValue + number
    }
}
