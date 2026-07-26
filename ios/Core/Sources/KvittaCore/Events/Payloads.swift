import Foundation

// Payloads never repeat the identifier that the envelope's `entityId` already carries
// (design doc §2): an ExpenseCreated's `entityId` *is* the expense id. One place for a fact,
// so the two can never disagree.

/// Decodes from any JSON object and ignores everything in it.
///
/// Used by events whose `entityId` says all there is to say. Being permissive here is what lets
/// a future `ExpenseDeleted` gain a `reason` field without older builds rejecting it.
public struct EmptyPayload: Hashable, Sendable, Codable {
    public init() {}

    public init(from decoder: any Decoder) throws {}

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode([String: String]())
    }
}

public struct GroupCreatedPayload: Hashable, Sendable, Codable {
    public let name: String
    public let currency: CurrencyCode

    public init(name: String, currency: CurrencyCode) {
        self.name = name
        self.currency = currency
    }
}

/// Every field optional: an update carries only what changed.
///
/// Changing `currency` after expenses exist reinterprets every stored amount, so the UI must not
/// offer it once a group has activity. Modelled here because the design doc lists it, not because
/// it is safe.
public struct GroupUpdatedPayload: Hashable, Sendable, Codable {
    public let name: String?
    public let currency: CurrencyCode?
    public let coverPhotoRef: String?

    public init(name: String? = nil, currency: CurrencyCode? = nil, coverPhotoRef: String? = nil) {
        self.name = name
        self.currency = currency
        self.coverPhotoRef = coverPhotoRef
    }
}

/// `linkedUserId` is nil for a placeholder member — someone who is in the group and owes money
/// but has never installed the app (design doc §5).
public struct MemberAddedPayload: Hashable, Sendable, Codable {
    public let displayName: String
    public let linkedUserId: UserID?

    public init(displayName: String, linkedUserId: UserID? = nil) {
        self.displayName = displayName
        self.linkedUserId = linkedUserId
    }
}

/// Settle-up. Money is never moved by the app; this records that it moved elsewhere.
public struct PaymentRecordedPayload: Hashable, Sendable, Codable {
    public let fromMemberId: MemberID
    public let toMemberId: MemberID
    public let currency: CurrencyCode
    public let amountMinor: Int64
    public let date: CalendarDate
    public let method: PaymentMethod
    public let note: String?

    public init(
        fromMemberId: MemberID,
        toMemberId: MemberID,
        currency: CurrencyCode,
        amountMinor: Int64,
        date: CalendarDate,
        method: PaymentMethod,
        note: String? = nil
    ) throws {
        guard amountMinor > 0 else {
            throw CoreError.nonPositiveAmount(field: "payment amountMinor", value: amountMinor)
        }
        guard fromMemberId != toMemberId else {
            throw CoreError.selfPayment(memberId: fromMemberId)
        }
        self.fromMemberId = fromMemberId
        self.toMemberId = toMemberId
        self.currency = currency
        self.amountMinor = amountMinor
        self.date = date
        self.method = method
        self.note = note
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            fromMemberId: container.decode(MemberID.self, forKey: .fromMemberId),
            toMemberId: container.decode(MemberID.self, forKey: .toMemberId),
            currency: container.decode(CurrencyCode.self, forKey: .currency),
            amountMinor: container.decode(Int64.self, forKey: .amountMinor),
            date: container.decode(CalendarDate.self, forKey: .date),
            method: container.decodeIfPresent(PaymentMethod.self, forKey: .method) ?? .cash,
            note: container.decodeIfPresent(String.self, forKey: .note)
        )
    }
}

/// How the money actually moved. A raw string so a method added by a newer client decodes here
/// as itself rather than failing.
public struct PaymentMethod: Hashable, Sendable, Codable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let cash = PaymentMethod(rawValue: "cash")
    public static let swish = PaymentMethod(rawValue: "swish")
    public static let mobilePay = PaymentMethod(rawValue: "mobilepay")
    public static let bankTransfer = PaymentMethod(rawValue: "banktransfer")

    public var description: String { rawValue }
}
