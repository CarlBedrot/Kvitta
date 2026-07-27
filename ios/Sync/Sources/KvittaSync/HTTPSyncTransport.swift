import Foundation
import KvittaCore

/// Where the server is and which build we are.
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

    /// Whether it is safe to send a bearer token to this host.
    ///
    /// The base URL is overridable at runtime through the `se.kvitta.syncBaseURL` default, which
    /// was harmless while requests only carried a user id. Now that every request carries a token,
    /// a plaintext host is somewhere to mail the token to. Localhost is exempted because the whole
    /// development loop runs against `http://localhost:5142`.
    public var isTrustworthy: Bool {
        if baseURL.scheme?.lowercased() == "https" { return true }

        let host = baseURL.host()?.lowercased()
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}

/// The real transport. Speaks the contract in `backend/Api/Endpoints/EventsEndpoints.cs`.
public struct HTTPSyncTransport: SyncTransport {
    private let configuration: SyncConfiguration
    private let session: URLSession
    private let tokens: AuthTokenProvider

    public init(
        configuration: SyncConfiguration,
        tokens: AuthTokenProvider,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.tokens = tokens
        self.session = session
    }

    private static let buildHeader = "X-Kvitta-Build"

    public func groups(as userId: UserID) async throws -> [GroupID] {
        let body = try await performAuthorised(makeAuthorisableRequest(path: "api/v1/groups"))

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
        var request = makeAuthorisableRequest(path: eventsPath(groupId))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try EventCoding.encode(events)

        let body = try await performAuthorised(request)

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
        let query = [
            URLQueryItem(name: "after", value: String(cursor)),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        let body = try await performAuthorised(makeAuthorisableRequest(path: eventsPath(groupId), query: query))

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

    /// Builds a request with everything *except* the credential.
    ///
    /// Authorization is stamped in `perform` instead, which is what lets a 401 be retried with a
    /// fresh token rather than replayed with the stale one. It also means there is exactly one
    /// place the header is set — it used to be two, and two places to remember is one too many.
    func makeAuthorisableRequest(path: String, query: [URLQueryItem] = []) -> URLRequest {
        var url = configuration.baseURL.appending(path: path)
        if !query.isEmpty {
            url = url.appending(queryItems: query)
        }

        var request = URLRequest(url: url, timeoutInterval: configuration.requestTimeout)
        request.setValue(String(configuration.buildNumber), forHTTPHeaderField: Self.buildHeader)
        return request
    }

    /// Sends the request, and on a 401 refreshes the session and sends it exactly once more.
    ///
    /// Once, not in a loop: if the second attempt is also refused then the token we just obtained
    /// is being rejected, and trying harder would only spin.
    func performAuthorised(_ request: URLRequest) async throws -> Data {
        guard configuration.isTrustworthy else {
            throw SyncError.malformedResponse(
                "Refusing to send credentials to \(configuration.baseURL.absoluteString) over plaintext."
            )
        }

        let token = await tokens.accessToken()
        guard let token else { throw SyncError.unauthorized }

        do {
            return try await send(request, token: token)
        } catch SyncError.unauthorized {
            let fresh = try await tokens.refreshedToken(replacing: token)
            return try await send(request, token: fresh)
        }
    }

    private func send(_ request: URLRequest, token: String) async throws -> Data {
        var authorised = request
        authorised.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: authorised)
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
        case 401:
            throw SyncError.unauthorized
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
