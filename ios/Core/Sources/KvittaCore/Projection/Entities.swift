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

    /// Where this payment stands with the person it was paid *to* (M8).
    ///
    /// Born `.confirmed` when nobody can ever press a button — the payee has no linked account —
    /// or when the payee recorded it themselves, which is its own confirmation. Otherwise born
    /// `.pending` and moved by `PaymentConfirmed`/`PaymentDisputed` from the payee; the last such
    /// event wins, same as every other correction in the log.
    public var status: PaymentStatus

    public init(
        id: PaymentID,
        payload: PaymentRecordedPayload,
        recordedBy: UserID,
        recordedAt: Timestamp,
        status: PaymentStatus = .confirmed
    ) {
        self.id = id
        self.payload = payload
        self.recordedBy = recordedBy
        self.recordedAt = recordedAt
        self.status = status
    }

    /// Whether this payment moves money in the balances shown for `asOf`.
    ///
    /// A pending payment does not — that is the whole feature — *until it ages out*: after
    /// `PaymentStatus.autoConfirmAfterDays` it counts as if confirmed. A debt stuck forever
    /// because the payee stopped opening the app would be worse than one settled optimistically,
    /// and the pending week is visible to everyone, which the silent one-sided version never was.
    /// Computed from the payment's own date at query time so the projection fold stays pure.
    public func countsTowardBalances(asOf: CalendarDate) -> Bool {
        switch status {
        case .confirmed: return true
        case .disputed: return false
        case .pending: return asOf.dayNumber - date.dayNumber >= PaymentStatus.autoConfirmAfterDays
        }
    }

    /// Pending and not yet aged out — the state that asks the payee for a decision.
    public func awaitsConfirmation(asOf: CalendarDate) -> Bool {
        status == .pending && !countsTowardBalances(asOf: asOf)
    }

    public var amountMinor: Int64 { payload.amountMinor }
    public var currency: CurrencyCode { payload.currency }
    public var date: CalendarDate { payload.date }
    public var fromMemberId: MemberID { payload.fromMemberId }
    public var toMemberId: MemberID { payload.toMemberId }
    public var method: PaymentMethod { payload.method }
}

/// The two-sided settle-up state machine (M8). Deliberately tiny: three states, last event wins.
public enum PaymentStatus: Hashable, Sendable {
    /// Counts in every balance. The terminal state of a happy settle-up.
    case confirmed
    /// Recorded by someone other than the payee; waiting for them. Does not move balances until
    /// confirmed or aged past `autoConfirmAfterDays`.
    case pending
    /// The payee said this never happened. Never counts; stays in history as its own warning.
    case disputed

    /// How long a pending payment waits before counting anyway.
    ///
    /// **The decision that makes M8 a milestone** (docs/session-prompts.md §7): auto-confirm
    /// after 7 days. What it trades away: a phantom payment eventually sticks if the payee
    /// never reacts — but it was visibly pending the whole week, the payee was nudged, and the
    /// alternative (pending forever) punishes the honest payer for the payee's inattention,
    /// which is the more common case in a friend group by far.
    public static let autoConfirmAfterDays = 7
}
