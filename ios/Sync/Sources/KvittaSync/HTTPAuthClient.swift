import Foundation
import KvittaCore

/// Talks to `/api/v1/auth`. The only part of the app that turns a proof of identity into a session.
public struct HTTPAuthClient: SessionRefresher {
    private let configuration: SyncConfiguration
    private let session: URLSession

    public init(configuration: SyncConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    /// Exchanges an Apple identity token for a Kvitta session.
    ///
    /// `nonce` is the raw value the client generated; the request to Apple carried its SHA-256.
    /// The server hashes this and compares, which is what stops a captured token being replayed
    /// into a different sign-in.
    public func signInWithApple(
        identityToken: String,
        nonce: String,
        displayName: String?
    ) async throws -> SessionTokens {
        try await post(
            path: "api/v1/auth/apple",
            body: AppleRequest(identityToken: identityToken, nonce: nonce, displayName: displayName)
        )
    }

    /// Signs in without Apple. Only works against a server running in Development.
    ///
    /// Sign in with Apple needs the `com.apple.developer.applesignin` entitlement, which needs a
    /// paid Apple Developer team. Until there is one, this is the only way to exercise the
    /// authenticated app at all — and it fails with a plain 404 against any server where it is not
    /// deliberately switched on.
    public func signInAsDeveloper(userId: UserID?, displayName: String?) async throws -> SessionTokens {
        try await post(
            path: "api/v1/auth/dev",
            body: DevRequest(userId: userId, displayName: displayName)
        )
    }

    public func refresh(using refreshToken: String) async throws -> SessionTokens {
        try await post(path: "api/v1/auth/refresh", body: RefreshRequest(refreshToken: refreshToken))
    }

    private func post(path: String, body: some Encodable) async throws -> SessionTokens {
        guard configuration.isTrustworthy else {
            throw SyncError.malformedResponse(
                "Refusing to send credentials to \(configuration.baseURL.absoluteString) over plaintext."
            )
        }

        var request = URLRequest(
            url: configuration.baseURL.appending(path: path),
            timeoutInterval: configuration.requestTimeout
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(String(configuration.buildNumber), forHTTPHeaderField: "X-Kvitta-Build")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SyncError.unreachable(String(describing: error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw SyncError.malformedResponse("Response was not HTTP.")
        }

        switch http.statusCode {
        case 200..<300:
            break
        case 401, 403:
            // Refused, not merely failed. Retrying will not help.
            throw SyncError.unauthorized
        case 426:
            throw SyncError.upgradeRequired(String(decoding: data, as: UTF8.self))
        default:
            throw SyncError.server(status: http.statusCode, detail: String(decoding: data, as: UTF8.self))
        }

        do {
            return try JSONDecoder().decode(SessionResponse.self, from: data).tokens(now: Date())
        } catch {
            throw SyncError.malformedResponse(String(describing: error))
        }
    }

    private struct AppleRequest: Encodable {
        let identityToken: String
        let nonce: String
        let displayName: String?
    }

    private struct DevRequest: Encodable {
        let userId: UserID?
        let displayName: String?
    }

    private struct RefreshRequest: Encodable {
        let refreshToken: String
    }

    private struct SessionResponse: Decodable {
        let userId: UserID
        let accessToken: String
        let expiresIn: Int
        let refreshToken: String

        func tokens(now: Date) -> SessionTokens {
            SessionTokens(
                userId: userId,
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: now.addingTimeInterval(TimeInterval(expiresIn))
            )
        }
    }
}
