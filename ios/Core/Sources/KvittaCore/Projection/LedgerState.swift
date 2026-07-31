import Foundation

/// Everything derived from the event log, across all groups.
public struct LedgerState: Hashable, Sendable {
    public var groups: [GroupID: GroupState]
    /// Every event id folded in so far, whether it changed anything or was skipped.
    ///
    /// This is what makes replay idempotent: an event that arrives twice — because it was pushed
    /// and then pulled back, or because a sync page overlapped — changes nothing the second time.
    public var appliedEventIds: Set<EventID>
    /// Events that were folded in but could not be applied, kept so sync status can show them
    /// instead of pretending they never arrived.
    public var skipped: [SkippedEvent]

    public init(
        groups: [GroupID: GroupState] = [:],
        appliedEventIds: Set<EventID> = [],
        skipped: [SkippedEvent] = []
    ) {
        self.groups = groups
        self.appliedEventIds = appliedEventIds
        self.skipped = skipped
    }

    public static let empty = LedgerState()

    public subscript(groupId: GroupID) -> GroupState? {
        groups[groupId]
    }

    public var groupsByName: [GroupState] {
        groups.values.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
    }
}

/// An event that was understood well enough to be counted, but not applied.
public struct SkippedEvent: Hashable, Sendable {
    public let eventId: EventID
    public let groupId: GroupID
    public let type: String
    public let reason: SkipReason

    public init(eventId: EventID, groupId: GroupID, type: String, reason: SkipReason) {
        self.eventId = eventId
        self.groupId = groupId
        self.type = type
        self.reason = reason
    }
}

public enum SkipReason: Hashable, Sendable, CustomStringConvertible {
    /// An event type this build does not know. Expected, not an error: a friend is on a newer
    /// version. Skip it and carry on (design doc §9).
    case unknownEventType(String)
    case unknownGroup
    case groupAlreadyExists
    case entityAlreadyExists
    case unknownExpense(ExpenseID)
    case unknownMember(MemberID)
    case memberAlreadyExists(MemberID)
    case currencyMismatch(expected: CurrencyCode, found: CurrencyCode)
    case unknownPayment(PaymentID)
    /// A confirmation or dispute from anyone but the payment's payee. Skipping it on every
    /// device is what makes the payee's word the only one that counts (M8).
    case notThePayee(PaymentID)

    public var description: String {
        switch self {
        case .unknownEventType(let type):
            return "Event type \"\(type)\" is not known to this build."
        case .unknownGroup:
            return "No such group in the local projection."
        case .groupAlreadyExists:
            return "The group already exists."
        case .entityAlreadyExists:
            return "An entity with this id already exists."
        case .unknownExpense(let id):
            return "No expense \(id) to act on."
        case .unknownMember(let id):
            return "Member \(id) is not in this group."
        case .memberAlreadyExists(let id):
            return "Member \(id) is already in this group."
        case .currencyMismatch(let expected, let found):
            return "Group currency is \(expected) but the event carried \(found)."
        case .unknownPayment(let id):
            return "Payment \(id) is not in this group."
        case .notThePayee(let id):
            return "Only the payee may confirm or dispute payment \(id)."
        }
    }
}
