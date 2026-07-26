import Foundation

/// A three-letter uppercase currency code.
///
/// Not an enum: a group could be created in a currency this build has never heard of, and the
/// right response to that is to carry it, not to fail decoding. Validation is on shape only.
public struct CurrencyCode: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public let code: String

    public init?(_ code: String) {
        guard code.count == 3,
              code.allSatisfy({ $0.isASCII && $0.isUppercase && $0.isLetter }) else { return nil }
        self.code = code
    }

    private init(validated code: String) {
        self.code = code
    }

    public static let sek = CurrencyCode(validated: "SEK")
    public static let dkk = CurrencyCode(validated: "DKK")
    public static let nok = CurrencyCode(validated: "NOK")
    public static let eur = CurrencyCode(validated: "EUR")

    public var description: String { code }

    public static func < (lhs: CurrencyCode, rhs: CurrencyCode) -> Bool {
        lhs.code < rhs.code
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = CurrencyCode(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "\"\(raw)\" is not a three-letter uppercase currency code."
            )
        }
        self = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(code)
    }
}
