import Foundation

/// Someone in a group. Not necessarily someone with an account.
///
/// `linkedUserId == nil` is the placeholder member from design doc §5 — the friend who will never
/// install the app but still owes for dinner. Expenses reference `MemberID`, never `UserID`, so
/// they keep working whether or not that person ever signs up.
public struct Member: Hashable, Sendable, Identifiable {
    public let id: MemberID
    public var displayName: String
    public var linkedUserId: UserID?
    /// A removed member keeps their history and their balance. Dropping them would make the
    /// group's balances stop summing to zero, and would hide money someone still owes.
    public var isActive: Bool

    public init(id: MemberID, displayName: String, linkedUserId: UserID? = nil, isActive: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.linkedUserId = linkedUserId
        self.isActive = isActive
    }
}

/// An expense as currently projected, plus where it came from.
public struct Expense: Hashable, Sendable, Identifiable {
    public let id: ExpenseID
    public var payload: ExpensePayload
    /// Soft delete. The event stays in the log, so "Visa borttagna" and restore both work.
    public var isDeleted: Bool
    public let createdBy: UserID
    public let createdAt: Timestamp
    public var lastModifiedBy: UserID
    public var lastModifiedAt: Timestamp
    /// How many `ExpenseUpdated` events have landed on this expense. 0 means never edited.
    public var revision: Int

    public init(
        id: ExpenseID,
        payload: ExpensePayload,
        isDeleted: Bool = false,
        createdBy: UserID,
        createdAt: Timestamp,
        lastModifiedBy: UserID,
        lastModifiedAt: Timestamp,
        revision: Int = 0
    ) {
        self.id = id
        self.payload = payload
        self.isDeleted = isDeleted
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.lastModifiedBy = lastModifiedBy
        self.lastModifiedAt = lastModifiedAt
        self.revision = revision
    }

    public var amountMinor: Int64 { payload.amountMinor }
    public var currency: CurrencyCode { payload.currency }
    public var date: CalendarDate { payload.date }
    public var title: String { payload.description }
    public var categoryId: String { payload.categoryId }
    public var wasEdited: Bool { revision > 0 }
}

/// A settle-up that happened somewhere else — cash, Swish, MobilePay — recorded here.
/// The app never moves money; it only writes down that money moved.
public struct Payment: Hashable, Sendable, Identifiable {
    public let id: PaymentID
    public var payload: PaymentRecordedPayload
    public let recordedBy: UserID
    public let recordedAt: Timestamp

    public init(
        id: PaymentID,
        payload: PaymentRecordedPayload,
        recordedBy: UserID,
        recordedAt: Timestamp
    ) {
        self.id = id
        self.payload = payload
        self.recordedBy = recordedBy
        self.recordedAt = recordedAt
    }

    public var amountMinor: Int64 { payload.amountMinor }
    public var currency: CurrencyCode { payload.currency }
    public var date: CalendarDate { payload.date }
    public var fromMemberId: MemberID { payload.fromMemberId }
    public var toMemberId: MemberID { payload.toMemberId }
    public var method: PaymentMethod { payload.method }
}
