import Foundation
import KvittaCore
import KvittaStorage
import KvittaSync

/// Whether you are signed in, and how to change that.
///
/// Signing in is optional by design. CLAUDE.md is explicit that the app must be fully functional
/// with the backend unreachable, so an account buys exactly one thing — a copy of your data that
/// survives losing the phone — and buys it without ever being required to add or read an expense.
@MainActor
@Observable
final class SessionModel {
    private(set) var userId: UserID?
    private(set) var isWorking = false
    private(set) var failure: String?

    private let tokens: AuthTokenProvider
    private let provider: any SignInProvider
    private let ledger: LedgerStore
    private let sync: SyncEngine

    init(
        tokens: AuthTokenProvider,
        provider: any SignInProvider,
        ledger: LedgerStore,
        sync: SyncEngine
    ) {
        self.tokens = tokens
        self.provider = provider
        self.ledger = ledger
        self.sync = sync
    }

    var isSignedIn: Bool { userId != nil }

    /// Reads the session the Keychain already holds, at launch.
    func restore() async {
        guard let existing = await tokens.userId else { return }
        adopt(existing)
    }

    func signIn(displayName: String?) async {
        isWorking = true
        failure = nil
        defer { isWorking = false }

        do {
            let session = try await provider.signIn(displayName: displayName)
            await tokens.signIn(session)
            adopt(session.userId)
            await sync.syncAll()
        } catch let error as SyncError {
            failure = message(for: error)
        } catch {
            failure = String(describing: error)
        }
    }

    /// Ends the session locally. The events stay exactly where they are.
    func signOut() async {
        await tokens.signOut()
        userId = nil
    }

    /// Adopts the account's identity for events written from now on.
    ///
    /// Deliberately does not touch anything already written — events are immutable. That has a
    /// consequence worth being honest about: a group created before signing in has its "you"
    /// member linked to the old device id, so the server will refuse it. Reconciling those needs a
    /// member-linking event, which is the next milestone.
    private func adopt(_ id: UserID) {
        userId = id
        ledger.setAuthor(id)
    }

    private func message(for error: SyncError) -> String {
        switch error {
        case .unreachable:
            return String(localized: "Kunde inte nå servern. Dina utgifter finns kvar på telefonen.")
        case .unauthorized:
            return "Inloggningen avvisades."
        case .upgradeRequired:
            return String(localized: "Den här versionen av Slice är för gammal.")
        case .server(let status, _):
            return status == 404
                ? "Servern tillåter inte utvecklarinloggning."
                : "Servern svarade med fel \(status)."
        case .notAMember, .malformedResponse:
            return "Inloggningen misslyckades."
        }
    }
}
