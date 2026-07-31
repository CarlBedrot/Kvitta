import Foundation
import KvittaCore
import KvittaSync

/// Keeps your Swish number on the server, and pulls co-members' numbers down.
///
/// The server side of `UserProfile.swishNumber` and `PayeeDirectory`: your number goes up as a
/// mutable profile field (never an event — a number in the immutable log could not be taken
/// back), and co-members' numbers come down into the same local directory the settle-up screen
/// already reads, so a fetched number and a typed one behave identically — including offline,
/// where the last fetch is simply what is remembered.
///
/// Failure is silence, like the rate fetch: a missing number leaves the type-it-yourself flow,
/// which is the whole feature working without an account.
@MainActor
@Observable
final class ProfileSyncer {
    private let transport: any ProfileTransport
    private let session: SessionModel
    private let defaults: UserDefaults

    /// What the server last accepted, so an unchanged number costs no request.
    private static let lastPushedKey = "se.kvitta.profile.lastPushedSwishNumber"

    init(
        transport: any ProfileTransport,
        session: SessionModel,
        defaults: UserDefaults = .standard
    ) {
        self.transport = transport
        self.session = session
        self.defaults = defaults
    }

    /// Pushes the profile's normalised number if it differs from what the server last accepted —
    /// including pushing `nil` to clear it, which is the point of it being a profile field.
    func push(_ profile: UserProfile) async {
        guard session.isSignedIn else { return }
        let number = profile.swishNumberForPayment
        guard number != defaults.string(forKey: Self.lastPushedKey) else { return }

        guard (try? await transport.updateProfile(swishNumber: number)) != nil else { return }
        if let number {
            defaults.set(number, forKey: Self.lastPushedKey)
        } else {
            defaults.removeObject(forKey: Self.lastPushedKey)
        }
    }

    /// Fetches the group's payee numbers into the directory the settle-up screen reads.
    func refreshPayees(in groupId: GroupID, into payees: PayeeDirectory) async {
        guard session.isSignedIn else { return }
        guard let fetched = try? await transport.payees(in: groupId) else { return }
        payees.absorb(fetched)
    }
}
