import Foundation
import KvittaCore

/// Where the server is and who we claim to be.
public struct SyncConfiguration: Hashable, Sendable {
    public let baseURL: URL
    /// Sent as `X-Kvitta-Build`, so the server can force an upgrade (design doc §9).
    public let buildNumber: Int
    public let pageLimit: Int
    public let requestTimeout: TimeInterval

    public init(
        baseURL: URL,
        buildNumber: Int = 1,
        pageLimit: Int = 500,
        requestTimeout: TimeInterval = 15
    ) {
        self.baseURL = baseURL
        self.buildNumber = buildNumber
        self.pageLimit = pageLimit
        self.requestTimeout = requestTimeout
    }
}

/// The real transport. Speaks the contract in `backend/Api/Endpoints/EventsEndpoints.cs`.
public struct HTTPSyncTransport: SyncTransport {
    private let configuration: SyncConfiguration
    private let session: URLSession

    public init(configuration: SyncConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    /// The M4 seam. When Sign in with Apple lands this becomes an Authorization bearer token and
    /// the server stops trusting the caller's word for who they are.
    private static let userHeader = "X-Kvitta-User-Id"
    private static let buildHeader = "X-Kvitta-Build"

    public func groups(as userId: UserID) async throws -> [GroupID] {
        let request = try makeRequest(path: "api/v1/groups", userId: userId)
        let body = try await perform(request)

        do {
            return try JSONDecoder().decode(GroupListBody.self, from: body).groupIds
        } catch {
            throw SyncError.malformedResponse(String(describing: error))
        }
    }

    public func push(
        groupId: GroupID,
        events: [EventEnvelope],
        as userId: UserID
    ) async throws -> PushResult {
        var request = try makeRequest(path: eventsPath(groupId), userId: userId)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try EventCoding.encode(events)

        let body = try await perform(request)

        do {
            let decoded = try JSONDecoder().decode(PushResponseBody.self, from: body)
            return PushResult(
                accepted: decoded.accepted.map {
                    PushResult.Acknowledgement(eventId: $0.eventId, serverSeq: $0.serverSeq)
                },
                rejected: decoded.rejected.map {
                    PushResult.Rejection(eventId: $0.eventId, code: $0.code, reason: $0.reason)
                }
            )
        } catch {
            throw SyncError.malformedResponse(String(describing: error))
        }
    }

    public func pull(
        groupId: GroupID,
        after cursor: Int64,
        limit: Int,
        as userId: UserID
    ) async throws -> PullResult {
        var components = URLComponents(
            url: configuration.baseURL.appending(path: eventsPath(groupId)),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "after", value: String(cursor)),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components?.url else {
            throw SyncError.malformedResponse("Could not build a pull URL.")
        }

        var request = URLRequest(url: url, timeoutInterval: configuration.requestTimeout)
        request.setValue(userId.rawValue.uuidString, forHTTPHeaderField: Self.userHeader)
        request.setValue(String(configuration.buildNumber), forHTTPHeaderField: Self.buildHeader)

        let body = try await perform(request)

        do {
            let decoded = try JSONDecoder().decode(PullResponseBody.self, from: body)
            return PullResult(events: decoded.events, nextCursor: decoded.nextCursor)
        } catch {
            throw SyncError.malformedResponse(String(describing: error))
        }
    }

    // MARK: - Plumbing

    private func eventsPath(_ groupId: GroupID) -> String {
        "api/v1/groups/\(groupId.rawValue.uuidString.lowercased())/events"
    }

    private func makeRequest(path: String, userId: UserID) throws -> URLRequest {
        var request = URLRequest(
            url: configuration.baseURL.appending(path: path),
            timeoutInterval: configuration.requestTimeout
        )
        request.setValue(userId.rawValue.uuidString, forHTTPHeaderField: Self.userHeader)
        request.setValue(String(configuration.buildNumber), forHTTPHeaderField: Self.buildHeader)
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Everything URLSession throws here is a "the server might as well not exist" case,
            // which is the normal state of affairs for an offline-first app rather than an error.
            throw SyncError.unreachable(String(describing: error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw SyncError.malformedResponse("Response was not HTTP.")
        }

        switch http.statusCode {
        case 200..<300:
            return data
        case 403:
            throw SyncError.notAMember
        case 426:
            throw SyncError.upgradeRequired(String(decoding: data, as: UTF8.self))
        default:
            throw SyncError.server(
                status: http.statusCode,
                detail: String(decoding: data, as: UTF8.self)
            )
        }
    }

    private struct PushResponseBody: Decodable {
        struct Accepted: Decodable {
            let eventId: EventID
            let serverSeq: Int64
        }

        struct Rejected: Decodable {
            let eventId: EventID
            let code: String
            let reason: String
        }

        let accepted: [Accepted]
        let rejected: [Rejected]
    }

    private struct PullResponseBody: Decodable {
        let events: [EventEnvelope]
        let nextCursor: Int64
    }

    private struct GroupListBody: Decodable {
        let groupIds: [GroupID]
    }
}
