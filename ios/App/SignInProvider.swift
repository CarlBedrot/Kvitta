import AuthenticationServices
import CryptoKit
import Foundation
import KvittaCore
import KvittaSync

/// Proves who you are, well enough for the server to issue a session.
///
/// A protocol with two implementations because Sign in with Apple needs the
/// `com.apple.developer.applesignin` entitlement, which needs a paid Apple Developer team. Until
/// there is one, `AppleSignInProvider` compiles but cannot run — `ASAuthorizationController` fails
/// at runtime without the entitlement — so `DeveloperSignInProvider` is what the app selects.
/// Swapping them is one line in `Bootstrap`, plus the entitlement file.
protocol SignInProvider: Sendable {
    func signIn(displayName: String?) async throws -> SessionTokens
}

/// The real thing. Compiled and reviewed, waiting on a Team ID to be switched on.
@MainActor
final class AppleSignInProvider: NSObject, SignInProvider {
    private let client: HTTPAuthClient

    init(client: HTTPAuthClient) {
        self.client = client
    }

    func signIn(displayName: String?) async throws -> SessionTokens {
        // A fresh nonce per attempt. Apple receives its SHA-256 and echoes that back inside the
        // identity token; the server hashes the raw value we send it and compares. That is what
        // stops an identity token captured from one sign-in being replayed into another.
        let rawNonce = Self.makeNonce()

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName]
        request.nonce = Self.sha256Hex(rawNonce)

        let credential = try await withCheckedThrowingContinuation { continuation in
            let controller = ASAuthorizationController(authorizationRequests: [request])
            let delegate = AuthorizationDelegate(continuation: continuation)
            self.delegate = delegate
            controller.delegate = delegate
            controller.presentationContextProvider = delegate
            controller.performRequests()
        }

        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            throw SyncError.unauthorized
        }

        // Apple hands over a name on the very first authorization only, so it is now or never.
        let name = credential.fullName.flatMap {
            PersonNameComponentsFormatter().string(from: $0).nilIfBlank
        }

        return try await client.signInWithApple(
            identityToken: identityToken,
            nonce: rawNonce,
            displayName: name ?? displayName
        )
    }

    /// Held because `ASAuthorizationController` does not retain its delegate.
    private var delegate: AuthorizationDelegate?

    private static func makeNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    /// Hex, lowercase — the format Apple puts in the `nonce` claim.
    private static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private final class AuthorizationDelegate: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private let continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>

    init(continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>) {
        self.continuation = continuation
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation.resume(throwing: SyncError.unauthorized)
            return
        }
        continuation.resume(returning: credential)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        continuation.resume(throwing: error)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
            ?? ASPresentationAnchor()
    }
}

/// Signs in against a server running in Development, with no Apple round-trip.
///
/// The account it creates is a real account in every other respect. The server refuses to mint one
/// for any user that has an Apple identity, and refuses to map this route at all outside
/// Development — so this cannot be pointed at anything real.
struct DeveloperSignInProvider: SignInProvider {
    let client: HTTPAuthClient
    /// Reuses the device's existing local id, so a developer signing in twice stays the same person.
    let userId: UserID

    func signIn(displayName: String?) async throws -> SessionTokens {
        try await client.signInAsDeveloper(userId: userId, displayName: displayName)
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespaces).isEmpty ? nil : self
    }
}
