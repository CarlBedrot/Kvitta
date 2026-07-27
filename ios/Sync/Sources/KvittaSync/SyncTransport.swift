import Foundation
import KvittaCore

/// What the server said about each event in a pushed batch.
public struct PushResult: Hashable, Sendable {
    public struct Acknowledgement: Hashable, Sendable {
        public let eventId: EventID
        public let serverSeq: Int64

        public init(eventId: EventID, serverSeq: Int64) {
            self.eventId = eventId
            self.serverSeq = serverSeq
        }
    }

    public struct Rejection: Hashable, Sendable {
        public let eventId: EventID
        /// A stable code such as `money_invariant_violated`, meant to be shown to a person.
        public let code: String
        public let reason: String

        public init(eventId: EventID, code: String, reason: String) {
            self.eventId = eventId
            self.code = code
            self.reason = reason
        }
    }

    public let accepted: [Acknowledgement]
    public let rejected: [Rejection]

    public init(accepted: [Acknowledgement], rejected: [Rejection]) {
        self.accepted = accepted
        self.rejected = rejected
    }
}

public struct PullResult: Hashable, Sendable {
    public let events: [EventEnvelope]
    public let nextCursor: Int64

    public init(events: [EventEnvelope], nextCursor: Int64) {
        self.events = events
        self.nextCursor = nextCursor
    }
}

/// Why a sync attempt did not complete.
///
/// The distinction that matters is `isRetryable`. A timeout means try again later; a 403 means
/// this will never work and something has to be shown to a human.
public enum SyncError: Error, Hashable, Sendable {
    /// No network, DNS failure, timeout, connection refused — the normal offline case.
    case unreachable(String)
    /// The caller is not a member of this group any more (design doc §7).
    case notAMember
    /// The server requires a newer build (design doc §9).
    case upgradeRequired(String)
    /// Any other HTTP failure.
    case server(status: Int, detail: String)
    /// The response did not parse.
    case malformedResponse(String)

    public var isRetryable: Bool {
        switch self {
        case .unreachable, .server:
            return true
        case .notAMember, .upgradeRequired, .malformedResponse:
            return false
        }
    }
}

/// The seam between the sync engine and an actual network.
///
/// Everything interesting about the engine — draining an outbox, handling rejections, not
/// corrupting the log when the server is down — is testable through this protocol with no
/// URLSession, no server, and no waiting.
public protocol SyncTransport: Sendable {
    /// The groups the server believes this user belongs to.
    ///
    /// Only a device with an empty database really needs this, but that device cannot work
    /// without it: it has no local groups to iterate, so it would sit showing an empty app while
    /// its whole history waited on the server (design doc §6, "new device / reinstall").
    func groups(as userId: UserID) async throws -> [GroupID]

    func push(
        groupId: GroupID,
        events: [EventEnvelope],
        as userId: UserID
    ) async throws -> PushResult

    func pull(
        groupId: GroupID,
        after cursor: Int64,
        limit: Int,
        as userId: UserID
    ) async throws -> PullResult
}
