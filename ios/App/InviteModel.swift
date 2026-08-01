import Foundation
import KvittaCore
import KvittaStorage
import KvittaSync

/// Creating an invite, and joining a group from one (design doc §7).
@MainActor
@Observable
final class InviteModel {
    /// What happened last, for the UI to show. Cleared when a new attempt starts.
    enum Outcome: Equatable {
        case joined(GroupID)
        case failed(String)
    }

    private(set) var isWorking = false
    private(set) var outcome: Outcome?
    private(set) var pendingInvite: GroupInvite?

    private let transport: any InviteTransport
    private let sync: SyncEngine
    private let session: SessionModel
    private let profile: UserProfile

    init(
        transport: any InviteTransport,
        sync: SyncEngine,
        session: SessionModel,
        profile: UserProfile
    ) {
        self.transport = transport
        self.sync = sync
        self.session = session
        self.profile = profile
    }

    func clear() {
        outcome = nil
        pendingInvite = nil
    }

    /// Mints a link to share. Requires an account: a group nobody can reach is not shareable.
    func createInvite(for groupId: GroupID) async {
        guard requireAccount() else { return }

        isWorking = true
        outcome = nil
        defer { isWorking = false }

        do {
            pendingInvite = try await transport.createInvite(groupId: groupId)
        } catch {
            outcome = .failed(message(for: error))
        }
    }

    /// Accepts a token, then pulls the group it let us into.
    ///
    /// The pull is the point. Accepting only writes the one event that makes you a member; the
    /// history you just inherited is still on the server, and until it is pulled the group would
    /// appear empty — which would look exactly like the invite having done nothing.
    func accept(token: UUID, claiming memberId: MemberID? = nil) async {
        guard requireAccount() else { return }

        isWorking = true
        outcome = nil
        defer { isWorking = false }

        do {
            let accepted = try await transport.acceptInvite(
                token: token,
                claiming: memberId,
                displayName: profile.displayName.isEmpty ? nil : profile.displayName
            )

            await sync.syncAll()
            outcome = .joined(accepted.groupId)
        } catch {
            outcome = .failed(message(for: error))
        }
    }

    /// Accepts from a pasted code or a full `slice://invite/<token>` link.
    func accept(rawCode: String) async {
        guard let token = Self.token(in: rawCode) else {
            outcome = .failed("Det där ser inte ut som en inbjudningskod.")
            return
        }

        await accept(token: token)
    }

    /// Pulls the token out of whatever the user had on their clipboard.
    ///
    /// Accepts the bare UUID as well as the link, because people paste both and telling somebody
    /// their perfectly good code is wrong on a technicality is a bad way to start.
    static func token(in raw: String) -> UUID? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = UUID(uuidString: trimmed) { return direct }

        // slice:// is the scheme since the rebrand; kvitta:// links from before it still open.
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "slice" || scheme == "kvitta" else {
            return nil
        }

        // slice://invite/<token> — host is "invite", the token is the single path component.
        let parts = ([url.host()] + url.pathComponents).compactMap { $0 }
        guard let last = parts.last(where: { $0 != "/" }) else { return nil }
        return UUID(uuidString: last)
    }

    private func requireAccount() -> Bool {
        guard session.isSignedIn else {
            outcome = .failed("Logga in först — en inbjudan behöver ett konto.")
            return false
        }
        return true
    }

    private func message(for error: any Error) -> String {
        guard let error = error as? SyncError else { return String(describing: error) }

        switch error {
        case .unreachable:
            return String(localized: "Kunde inte nå servern.")
        case .unauthorized:
            return String(localized: "Du är utloggad. Logga in igen.")
        case .notAMember:
            return String(localized: "Du är inte med i den gruppen.")
        case .upgradeRequired:
            return String(localized: "Den här versionen av Slice är för gammal.")
        case .server(let status, _):
            switch status {
            case 404: return String(localized: "Inbjudan finns inte.")
            case 409: return String(localized: "Den platsen är redan någon annans.")
            case 410: return String(localized: "Inbjudan har gått ut. Be om en ny.")
            default: return String(localized: "Servern svarade med fel \(status).")
            }
        case .malformedResponse:
            return String(localized: "Något gick fel med inbjudan.")
        }
    }
}
