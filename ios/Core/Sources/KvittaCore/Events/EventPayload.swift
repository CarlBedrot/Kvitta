import Foundation

/// The body of an event, discriminated by the envelope's `type`.
///
/// The `unknown` case is load-bearing, not defensive padding. Two people in the same group will
/// run different builds — one of them updates, adds an expense using a feature the other's build
/// has never heard of, and that event lands in the other's sync page. It has to decode, be
/// storable, be re-encodable byte-for-byte, and be quietly skipped during projection. Anything
/// else means one friend's upgrade breaks another friend's app.
public enum EventPayload: Hashable, Sendable {
    case groupCreated(GroupCreatedPayload)
    case groupUpdated(GroupUpdatedPayload)
    case memberAdded(MemberAddedPayload)
    case memberRemoved(EmptyPayload)
    case expenseCreated(ExpensePayload)
    case expenseUpdated(ExpensePayload)
    case expenseDeleted(EmptyPayload)
    case expenseRestored(EmptyPayload)
    case paymentRecorded(PaymentRecordedPayload)
    case unknown(type: String, raw: JSONValue)

    /// The wire `type` string. Derived from the case so the envelope's type and its payload can
    /// never drift apart.
    public var eventType: String {
        switch self {
        case .groupCreated: return EventType.groupCreated
        case .groupUpdated: return EventType.groupUpdated
        case .memberAdded: return EventType.memberAdded
        case .memberRemoved: return EventType.memberRemoved
        case .expenseCreated: return EventType.expenseCreated
        case .expenseUpdated: return EventType.expenseUpdated
        case .expenseDeleted: return EventType.expenseDeleted
        case .expenseRestored: return EventType.expenseRestored
        case .paymentRecorded: return EventType.paymentRecorded
        case .unknown(let type, _): return type
        }
    }

    public var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }

    /// The expense body of a create or update event, if this is one.
    public var expense: ExpensePayload? {
        switch self {
        case .expenseCreated(let payload), .expenseUpdated(let payload): return payload
        default: return nil
        }
    }
}

/// The wire type strings, in one place so the client and the .NET server cannot disagree by typo.
public enum EventType {
    public static let groupCreated = "GroupCreated"
    public static let groupUpdated = "GroupUpdated"
    public static let memberAdded = "MemberAdded"
    public static let memberRemoved = "MemberRemoved"
    public static let expenseCreated = "ExpenseCreated"
    public static let expenseUpdated = "ExpenseUpdated"
    public static let expenseDeleted = "ExpenseDeleted"
    public static let expenseRestored = "ExpenseRestored"
    public static let paymentRecorded = "PaymentRecorded"

    public static let allKnown: Set<String> = [
        groupCreated, groupUpdated,
        memberAdded, memberRemoved,
        expenseCreated, expenseUpdated, expenseDeleted, expenseRestored,
        paymentRecorded
    ]
}
