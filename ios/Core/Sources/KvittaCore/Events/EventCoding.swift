import Foundation

/// JSON in and out for events, with one rule: a single bad event must never cost you the page
/// it arrived in.
public enum EventCoding {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Stable key order so two encodings of equal values are byte-identical — which is what
        // lets tests compare payloads and lets the outbox deduplicate cheaply.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    public static func encode(_ event: EventEnvelope) throws -> Data {
        try makeEncoder().encode(event)
    }

    public static func encode(_ events: [EventEnvelope]) throws -> Data {
        try makeEncoder().encode(events)
    }

    public static func decode(_ data: Data) throws -> EventEnvelope {
        try makeDecoder().decode(EventEnvelope.self, from: data)
    }

    /// Decodes a sync page one event at a time.
    ///
    /// A malformed event — a known type whose payload breaks the money invariant, say, or a
    /// corrupt amount — is *rejected individually* rather than throwing out the whole batch. This
    /// is what Session 3 needs behind "these expenses could not sync": the good events apply, the
    /// bad ones are surfaced with a reason instead of vanishing.
    ///
    /// An *unknown* event type is not a rejection. It decodes fine, into `.unknown`.
    public static func decodeBatch(_ data: Data) throws -> BatchDecodeResult {
        let decoder = makeDecoder()
        let encoder = makeEncoder()
        let elements = try decoder.decode([JSONValue].self, from: data)

        var accepted: [EventEnvelope] = []
        var rejected: [RejectedEvent] = []
        accepted.reserveCapacity(elements.count)

        for (index, element) in elements.enumerated() {
            do {
                let elementData = try encoder.encode(element)
                accepted.append(try decoder.decode(EventEnvelope.self, from: elementData))
            } catch {
                rejected.append(
                    RejectedEvent(
                        index: index,
                        eventId: element["eventId"]?.stringValue.flatMap(EventID.init(uuidString:)),
                        reason: String(describing: error),
                        raw: element
                    )
                )
            }
        }

        return BatchDecodeResult(accepted: accepted, rejected: rejected)
    }
}

public struct BatchDecodeResult: Hashable, Sendable {
    public let accepted: [EventEnvelope]
    public let rejected: [RejectedEvent]

    public init(accepted: [EventEnvelope], rejected: [RejectedEvent]) {
        self.accepted = accepted
        self.rejected = rejected
    }
}

/// An event that could not be understood, kept whole so it can be shown, logged, or retried
/// after an app update rather than silently dropped.
public struct RejectedEvent: Hashable, Sendable {
    public let index: Int
    public let eventId: EventID?
    public let reason: String
    public let raw: JSONValue

    public init(index: Int, eventId: EventID?, reason: String, raw: JSONValue) {
        self.index = index
        self.eventId = eventId
        self.reason = reason
        self.raw = raw
    }
}
