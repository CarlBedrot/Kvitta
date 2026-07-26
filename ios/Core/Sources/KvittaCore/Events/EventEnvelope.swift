import Foundation

/// One immutable entry in a group's event log, exactly as design doc §2 describes it.
///
/// Events are never edited. A correction is a new `ExpenseUpdated` carrying the whole new expense;
/// the old version stays in the log and becomes the edit history the UI shows for free.
public struct EventEnvelope: Hashable, Sendable {
    /// Generated on device. The idempotency key: pushing the same event twice is a no-op, both
    /// on the server's unique index and in `Projector`.
    public let eventId: EventID
    public let groupId: GroupID
    /// The expense / member / payment / group this event concerns. Interpretation depends on
    /// `type`; see `EventPayload`.
    public let entityId: UUID
    public let schemaVersion: Int
    public let authorId: UserID
    /// Display only. Never used for ordering — clocks on other people's phones are not ordered.
    public let clientTimestamp: Timestamp
    /// Assigned by the server, strictly monotonic per group. `nil` means this event is still in
    /// the outbox and has not been acknowledged.
    public let serverSeq: Int64?
    public let payload: EventPayload

    public init(
        eventId: EventID = EventID(),
        groupId: GroupID,
        entityId: UUID,
        schemaVersion: Int = EventEnvelope.currentSchemaVersion,
        authorId: UserID,
        clientTimestamp: Timestamp,
        serverSeq: Int64? = nil,
        payload: EventPayload
    ) {
        self.eventId = eventId
        self.groupId = groupId
        self.entityId = entityId
        self.schemaVersion = schemaVersion
        self.authorId = authorId
        self.clientTimestamp = clientTimestamp
        self.serverSeq = serverSeq
        self.payload = payload
    }

    public static let currentSchemaVersion = 1

    public var type: String { payload.eventType }

    public var isAcknowledged: Bool { serverSeq != nil }

    /// The same event with the sequence number the server assigned it.
    public func acknowledged(serverSeq: Int64) -> EventEnvelope {
        EventEnvelope(
            eventId: eventId,
            groupId: groupId,
            entityId: entityId,
            schemaVersion: schemaVersion,
            authorId: authorId,
            clientTimestamp: clientTimestamp,
            serverSeq: serverSeq,
            payload: payload
        )
    }

    // MARK: - Typed entity accessors

    public var expenseId: ExpenseID { ExpenseID(rawValue: entityId) }
    public var memberId: MemberID { MemberID(rawValue: entityId) }
    public var paymentId: PaymentID { PaymentID(rawValue: entityId) }
}

extension EventEnvelope: Codable {
    private enum CodingKeys: String, CodingKey {
        case eventId, groupId, entityId, type, schemaVersion, authorId
        case clientTimestamp, serverSeq, payload
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        let payload: EventPayload
        switch type {
        case EventType.groupCreated:
            payload = .groupCreated(try container.decode(GroupCreatedPayload.self, forKey: .payload))
        case EventType.groupUpdated:
            payload = .groupUpdated(try container.decode(GroupUpdatedPayload.self, forKey: .payload))
        case EventType.memberAdded:
            payload = .memberAdded(try container.decode(MemberAddedPayload.self, forKey: .payload))
        case EventType.memberRemoved:
            payload = .memberRemoved(try container.decode(EmptyPayload.self, forKey: .payload))
        case EventType.expenseCreated:
            payload = .expenseCreated(try container.decode(ExpensePayload.self, forKey: .payload))
        case EventType.expenseUpdated:
            payload = .expenseUpdated(try container.decode(ExpensePayload.self, forKey: .payload))
        case EventType.expenseDeleted:
            payload = .expenseDeleted(try container.decode(EmptyPayload.self, forKey: .payload))
        case EventType.expenseRestored:
            payload = .expenseRestored(try container.decode(EmptyPayload.self, forKey: .payload))
        case EventType.paymentRecorded:
            payload = .paymentRecorded(
                try container.decode(PaymentRecordedPayload.self, forKey: .payload)
            )
        default:
            // Unknown type: keep the body verbatim rather than failing the whole sync page.
            let raw = try container.decodeIfPresent(JSONValue.self, forKey: .payload) ?? .null
            payload = .unknown(type: type, raw: raw)
        }

        self.init(
            eventId: try container.decode(EventID.self, forKey: .eventId),
            groupId: try container.decode(GroupID.self, forKey: .groupId),
            entityId: try container.decode(UUID.self, forKey: .entityId),
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
                ?? EventEnvelope.currentSchemaVersion,
            authorId: try container.decode(UserID.self, forKey: .authorId),
            clientTimestamp: try container.decode(Timestamp.self, forKey: .clientTimestamp),
            serverSeq: try container.decodeIfPresent(Int64.self, forKey: .serverSeq),
            payload: payload
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventId, forKey: .eventId)
        try container.encode(groupId, forKey: .groupId)
        try container.encode(entityId, forKey: .entityId)
        try container.encode(type, forKey: .type)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(authorId, forKey: .authorId)
        try container.encode(clientTimestamp, forKey: .clientTimestamp)
        try container.encodeIfPresent(serverSeq, forKey: .serverSeq)

        switch payload {
        case .groupCreated(let value): try container.encode(value, forKey: .payload)
        case .groupUpdated(let value): try container.encode(value, forKey: .payload)
        case .memberAdded(let value): try container.encode(value, forKey: .payload)
        case .memberRemoved(let value): try container.encode(value, forKey: .payload)
        case .expenseCreated(let value): try container.encode(value, forKey: .payload)
        case .expenseUpdated(let value): try container.encode(value, forKey: .payload)
        case .expenseDeleted(let value): try container.encode(value, forKey: .payload)
        case .expenseRestored(let value): try container.encode(value, forKey: .payload)
        case .paymentRecorded(let value): try container.encode(value, forKey: .payload)
        case .unknown(_, let raw): try container.encode(raw, forKey: .payload)
        }
    }
}

extension EventEnvelope {
    /// Replay order: acknowledged events by the sequence the server agreed on, then anything
    /// still in the outbox, in the order it was created (design doc §6, "ordering subtlety").
    public static func sortedForReplay(
        synced: [EventEnvelope],
        pending: [EventEnvelope] = []
    ) -> [EventEnvelope] {
        let ordered = synced
            .filter { $0.serverSeq != nil }
            .sorted { ($0.serverSeq ?? 0) < ($1.serverSeq ?? 0) }
        return ordered + synced.filter { $0.serverSeq == nil } + pending
    }
}
