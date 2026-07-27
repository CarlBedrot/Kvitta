import Foundation
import Testing
import KvittaCore
import KvittaCoreTestSupport
@testable import KvittaSync

/// A refresher that counts how often it is asked, and can be made slow or made to fail.
private actor StubRefresher: SessionRefresher {
    enum Behaviour: Sendable {
        case succeed
        /// Refused — the chain is dead.
        case refuse
        /// Could not be attempted — offline.
        case unreachable
    }

    private var behaviour: Behaviour
    private let delay: Duration
    private(set) var callCount = 0
    private var issued = 0

    init(behaviour: Behaviour = .succeed, delay: Duration = .zero) {
        self.behaviour = behaviour
        self.delay = delay
    }

    func set(_ behaviour: Behaviour) {
        self.behaviour = behaviour
    }

    func refresh(using refreshToken: String) async throws -> SessionTokens {
        callCount += 1

        if delay > .zero {
            try? await Task.sleep(for: delay)
        }

        switch behaviour {
        case .succeed:
            issued += 1
            return SessionTokens(
                userId: Fixtures.authorId,
                accessToken: "access-\(issued)",
                refreshToken: "refresh-\(issued)",
                expiresAt: Date().addingTimeInterval(3600)
            )
        case .refuse:
            throw SyncError.unauthorized
        case .unreachable:
            throw SyncError.unreachable("no network")
        }
    }
}

private func signedInStore() -> InMemoryTokenStore {
    InMemoryTokenStore(
        SessionTokens(
            userId: Fixtures.authorId,
            accessToken: "stale",
            refreshToken: "refresh-0",
            expiresAt: Date().addingTimeInterval(-60)
        )
    )
}

@Suite("Auth token provider")
struct AuthTokenProviderTests {

    @Test("A refresh replaces the stored session")
    func refreshStoresTheNewSession() async throws {
        let store = signedInStore()
        let provider = AuthTokenProvider(store: store, refresher: StubRefresher())

        let token = try await provider.refreshedToken(replacing: "stale")

        #expect(token == "access-1")
        #expect(store.load()?.refreshToken == "refresh-1")
    }

    @Test("Many simultaneous 401s cause exactly one refresh")
    func concurrentRefreshesAreSingleFlighted() async throws {
        // The bug this prevents is self-inflicted and nasty: syncAll pulls every group at once, so
        // an expired token produces several 401s at the same moment. Without single-flight each
        // one presents the same refresh token, the server reads the repeats as a stolen token,
        // revokes the whole family, and the app has logged itself out.
        let refresher = StubRefresher(delay: .milliseconds(50))
        let provider = AuthTokenProvider(store: signedInStore(), refresher: refresher)

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<8 {
                group.addTask { try await provider.refreshedToken(replacing: "stale") }
            }

            var results: [String] = []
            for try await token in group { results.append(token) }
            return results
        }

        #expect(await refresher.callCount == 1)
        #expect(tokens.count == 8)
        #expect(Set(tokens) == ["access-1"])
    }

    @Test("A caller holding an already-replaced token gets the current one without refreshing")
    func staleCallerSkipsTheRefresh() async throws {
        let refresher = StubRefresher()
        let store = signedInStore()
        let provider = AuthTokenProvider(store: store, refresher: refresher)

        _ = try await provider.refreshedToken(replacing: "stale")
        // A request that was already in flight now comes back 401 holding the old token.
        let token = try await provider.refreshedToken(replacing: "stale")

        #expect(token == "access-1")
        #expect(await refresher.callCount == 1)
    }

    @Test("A refused refresh clears the session and reports being signed out")
    func refusedRefreshSignsOut() async throws {
        let store = signedInStore()
        let provider = AuthTokenProvider(store: store, refresher: StubRefresher(behaviour: .refuse))

        await #expect(throws: SyncError.unauthorized) {
            try await provider.refreshedToken(replacing: "stale")
        }

        #expect(store.load() == nil)
    }

    @Test("Being offline during a refresh does not sign anyone out")
    func offlineRefreshKeepsTheSession() async throws {
        // Throwing away a working refresh token because a train went into a tunnel would be a
        // spectacular own goal: the user would be signed out for the crime of being offline, in an
        // app whose entire premise is working offline.
        let store = signedInStore()
        let provider = AuthTokenProvider(store: store, refresher: StubRefresher(behaviour: .unreachable))

        await #expect(throws: SyncError.self) {
            try await provider.refreshedToken(replacing: "stale")
        }

        #expect(store.load()?.refreshToken == "refresh-0")
    }

    @Test("Refreshing while signed out is refused rather than attempted")
    func signedOutRefreshThrows() async throws {
        let refresher = StubRefresher()
        let provider = AuthTokenProvider(store: InMemoryTokenStore(), refresher: refresher)

        await #expect(throws: SyncError.unauthorized) {
            try await provider.refreshedToken(replacing: nil)
        }

        #expect(await refresher.callCount == 0)
    }

    @Test("Signing out forgets the session")
    func signOutClearsEverything() async throws {
        let store = signedInStore()
        let provider = AuthTokenProvider(store: store, refresher: StubRefresher())

        await provider.signOut()

        #expect(store.load() == nil)
        #expect(await provider.accessToken() == nil)
        #expect(await provider.isSignedIn == false)
    }
}
