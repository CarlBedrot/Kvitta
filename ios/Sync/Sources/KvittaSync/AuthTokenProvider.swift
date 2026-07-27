import Foundation
import KvittaCore

/// Exchanges a refresh token for a new session. The seam that keeps the provider testable offline.
public protocol SessionRefresher: Sendable {
    func refresh(using refreshToken: String) async throws -> SessionTokens
}

/// Holds the session and hands out bearer tokens, refreshing when the server says to.
///
/// An actor because the single-flight rule below is the whole point, and that rule is only
/// meaningful if concurrent callers actually serialise.
public actor AuthTokenProvider {
    private let store: any TokenStore
    private let refresher: any SessionRefresher

    /// The in-progress refresh, if there is one. This is the single-flight latch.
    private var inFlight: Task<SessionTokens, Error>?

    public init(store: any TokenStore, refresher: any SessionRefresher) {
        self.store = store
        self.refresher = refresher
    }

    public var isSignedIn: Bool {
        store.load() != nil
    }

    public var userId: UserID? {
        store.load()?.userId
    }

    /// The token to put on the next request, or nil when signed out.
    public func accessToken() -> String? {
        store.load()?.accessToken
    }

    public func signIn(_ tokens: SessionTokens) {
        inFlight?.cancel()
        inFlight = nil
        store.save(tokens)
    }

    public func signOut() {
        inFlight?.cancel()
        inFlight = nil
        store.clear()
    }

    /// Renews the session, or throws `SyncError.unauthorized` if it cannot.
    ///
    /// Concurrent callers share one attempt. Without that, a sync that fires several requests at
    /// once — which `syncAll` does, one pull per group — would see several 401s, start several
    /// refreshes, and present the same refresh token several times. The server treats a second
    /// presentation of a spent token as theft and revokes the entire family, so the client would
    /// have signed *itself* out. The bug would be rare, look like a server fault, and be miserable
    /// to reproduce.
    public func refreshedToken(replacing stale: String?) async throws -> String {
        // Somebody else already refreshed while this caller was waiting on the network.
        if let current = store.load()?.accessToken, current != stale {
            return current
        }

        if let existing = inFlight {
            return try await existing.value.accessToken
        }

        guard let refreshToken = store.load()?.refreshToken else {
            throw SyncError.unauthorized
        }

        let task = Task { [refresher] in
            try await refresher.refresh(using: refreshToken)
        }
        inFlight = task

        defer { inFlight = nil }

        do {
            let tokens = try await task.value
            store.save(tokens)
            return tokens.accessToken
        } catch let error as SyncError where error.isRetryable {
            // The refresh could not be attempted rather than being refused. Keep the session:
            // throwing away a perfectly good refresh token because the train went into a tunnel
            // would sign the user out for being offline.
            throw error
        } catch {
            // Refused. The chain is dead — possibly revoked because it leaked — and holding onto
            // it would mean retrying a token the server will never accept again.
            store.clear()
            throw SyncError.unauthorized
        }
    }
}
