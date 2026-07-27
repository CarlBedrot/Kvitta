import Foundation
import KvittaCore

/// The pair of tokens a signed-in session consists of.
public struct SessionTokens: Hashable, Sendable, Codable {
    public let userId: UserID
    public let accessToken: String
    public let refreshToken: String
    /// When the access token stops being accepted. Advisory: the server decides, not us.
    public let expiresAt: Date

    public init(userId: UserID, accessToken: String, refreshToken: String, expiresAt: Date) {
        self.userId = userId
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

/// Where the session lives between launches.
///
/// A protocol rather than reaching straight for the Keychain, because `swift test` from `ios/Sync/`
/// runs on macOS against the *macOS* keychain, where an unsigned test host can prompt or simply
/// fail. Tests use the in-memory implementation; the app uses the real one.
public protocol TokenStore: Sendable {
    func load() -> SessionTokens?
    func save(_ tokens: SessionTokens)
    func clear()
}

/// The real thing, on the device.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    public init(service: String = "se.kvitta.session", account: String = "tokens") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    public func load() -> SessionTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(SessionTokens.self, from: data)
    }

    public func save(_ tokens: SessionTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }

        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecValueData as String] = data
        // AfterFirstUnlock rather than WhenUnlocked, because M5's silent push needs to sync while
        // the phone is locked in a pocket. ThisDeviceOnly, and deliberately *not* synchronizable:
        // a refresh token riding iCloud Keychain to a second device would present the same token
        // twice, trip the server's reuse detection, and sign both devices out.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        SecItemAdd(query as CFDictionary, nil)
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// For tests and previews.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: SessionTokens?

    public init(_ tokens: SessionTokens? = nil) {
        self.tokens = tokens
    }

    public func load() -> SessionTokens? {
        lock.withLock { tokens }
    }

    public func save(_ tokens: SessionTokens) {
        lock.withLock { self.tokens = tokens }
    }

    public func clear() {
        lock.withLock { tokens = nil }
    }
}
