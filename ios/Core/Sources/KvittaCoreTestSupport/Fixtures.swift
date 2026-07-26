import Foundation
import KvittaCore

/// Identifiers with a known sort order, so tests can assert *which* member gets the leftover öre
/// rather than just that the amounts add up.
public enum Fixtures {
    public static let currency = CurrencyCode.sek
    public static let date = CalendarDate(year: 2026, month: 7, day: 21)!
    public static let timestamp = Timestamp(iso8601: "2026-07-21T18:30:00Z")!

    /// `member(1) < member(2) < member(3)` by the same byte ordering `Allocator` sorts on.
    public static func member(_ index: Int) -> MemberID {
        MemberID(uuidString: "00000000-0000-0000-0000-\(pad(index, 12))")!
    }

    public static func expense(_ index: Int) -> ExpenseID {
        ExpenseID(uuidString: "00000000-0000-0000-0001-\(pad(index, 12))")!
    }

    public static func payment(_ index: Int) -> PaymentID {
        PaymentID(uuidString: "00000000-0000-0000-0002-\(pad(index, 12))")!
    }

    public static let groupId = GroupID(uuidString: "00000000-0000-0000-000a-000000000001")!
    public static let authorId = UserID(uuidString: "00000000-0000-0000-000b-000000000001")!

    public static func money(_ minor: Int64) -> Money {
        Money(amountMinor: minor, currency: currency)
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}

/// Builds envelopes with monotonically increasing `serverSeq`, which is the order the projector
/// is entitled to assume.
public struct EventFactory {
    public let groupId: GroupID
    public let authorId: UserID
    private var seq: Int64 = 0

    public init(groupId: GroupID = Fixtures.groupId, authorId: UserID = Fixtures.authorId) {
        self.groupId = groupId
        self.authorId = authorId
    }

    public mutating func make(
        entityId: UUID,
        payload: EventPayload,
        eventId: EventID = EventID(),
        acknowledged: Bool = true
    ) -> EventEnvelope {
        seq += 1
        return EventEnvelope(
            eventId: eventId,
            groupId: groupId,
            entityId: entityId,
            authorId: authorId,
            clientTimestamp: Timestamp(epochMilliseconds: 1_784_000_000_000 + seq),
            serverSeq: acknowledged ? seq : nil,
            payload: payload
        )
    }

    public mutating func groupCreated(name: String = "Fjällresan", currency: CurrencyCode = Fixtures.currency) -> EventEnvelope {
        make(
            entityId: groupId.rawValue,
            payload: .groupCreated(GroupCreatedPayload(name: name, currency: currency))
        )
    }

    public mutating func memberAdded(_ memberId: MemberID, name: String) -> EventEnvelope {
        make(
            entityId: memberId.rawValue,
            payload: .memberAdded(MemberAddedPayload(displayName: name))
        )
    }

    public mutating func memberRemoved(_ memberId: MemberID) -> EventEnvelope {
        make(entityId: memberId.rawValue, payload: .memberRemoved(EmptyPayload()))
    }

    public mutating func expenseCreated(_ expenseId: ExpenseID, _ payload: ExpensePayload) -> EventEnvelope {
        make(entityId: expenseId.rawValue, payload: .expenseCreated(payload))
    }

    public mutating func expenseUpdated(_ expenseId: ExpenseID, _ payload: ExpensePayload) -> EventEnvelope {
        make(entityId: expenseId.rawValue, payload: .expenseUpdated(payload))
    }

    public mutating func expenseDeleted(_ expenseId: ExpenseID) -> EventEnvelope {
        make(entityId: expenseId.rawValue, payload: .expenseDeleted(EmptyPayload()))
    }

    public mutating func expenseRestored(_ expenseId: ExpenseID) -> EventEnvelope {
        make(entityId: expenseId.rawValue, payload: .expenseRestored(EmptyPayload()))
    }

    public mutating func paymentRecorded(_ paymentId: PaymentID, _ payload: PaymentRecordedPayload) -> EventEnvelope {
        make(entityId: paymentId.rawValue, payload: .paymentRecorded(payload))
    }

    public mutating func unknownType(_ type: String, entityId: UUID = UUID()) -> EventEnvelope {
        seq += 1
        return EventEnvelope(
            groupId: groupId,
            entityId: entityId,
            authorId: authorId,
            clientTimestamp: Timestamp(epochMilliseconds: 1_784_000_000_000 + seq),
            serverSeq: seq,
            payload: .unknown(
                type: type,
                raw: .object(["someFutureField": .string("hello from a newer build")])
            )
        )
    }
}
