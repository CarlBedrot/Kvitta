import Foundation
import KvittaCore

/// Your payment profile on the server, and the co-members' numbers it makes visible.
///
/// This is the "server-side profile field, not an event" CLAUDE.md's payment rules point to. A
/// Swish number must never enter the immutable log — it could never be taken back — but a mutable
/// profile column the owner controls has none of that permanence: change it or clear it and it
/// stops being served.
///
/// Separate from `SyncTransport` for the same reason `InviteTransport` is: syncing is a loop that
/// runs on its own, and a profile is something a person edits.
public protocol ProfileTransport: Sendable {
    /// Sets or clears your own Swish number. Pass `nil` to clear.
    func updateProfile(swishNumber: String?) async throws

    /// The Swish numbers of a group's members, keyed by member — only members who linked an
    /// account and chose to set a number appear. Members only; placeholders can never appear.
    func payees(in groupId: GroupID) async throws -> [MemberID: String]
}

extension HTTPSyncTransport: ProfileTransport {
    public func updateProfile(swishNumber: String?) async throws {
        var request = makeAuthorisableRequest(path: "api/v1/me/profile")
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ProfileBody(swishNumber: swishNumber))
        _ = try await performAuthorised(request)
    }

    public func payees(in groupId: GroupID) async throws -> [MemberID: String] {
        let body = try await performAuthorised(makeAuthorisableRequest(
            path: "api/v1/groups/\(groupId.rawValue.uuidString.lowercased())/payees"
        ))

        do {
            let decoded = try JSONDecoder().decode(PayeesBody.self, from: body)
            return Dictionary(
                decoded.payees.map { ($0.memberId, $0.swishNumber) },
                uniquingKeysWith: { first, _ in first }
            )
        } catch {
            throw SyncError.malformedResponse(String(describing: error))
        }
    }

    private struct ProfileBody: Encodable {
        let swishNumber: String?
    }

    private struct PayeesBody: Decodable {
        let payees: [Entry]

        struct Entry: Decodable {
            let memberId: MemberID
            let swishNumber: String
        }
    }
}
