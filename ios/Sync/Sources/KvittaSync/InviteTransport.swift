import Foundation
import KvittaCore

public struct GroupInvite: Hashable, Sendable {
    public let token: UUID
    public let expiresAt: Date
    /// `kvitta://invite/<token>`, ready to share.
    public let url: URL

    public init(token: UUID, expiresAt: Date, url: URL) {
        self.token = token
        self.expiresAt = expiresAt
        self.url = url
    }
}

public struct AcceptedInvite: Hashable, Sendable {
    public let groupId: GroupID
    public let memberId: MemberID

    public init(groupId: GroupID, memberId: MemberID) {
        self.groupId = groupId
        self.memberId = memberId
    }
}

/// Creating and accepting invite links (design doc §7).
///
/// Separate from `SyncTransport` on purpose: syncing is a loop that runs on its own, and inviting
/// is something a person does. Keeping them apart means the sync engine's stub does not have to
/// grow methods it will never call.
public protocol InviteTransport: Sendable {
    func createInvite(groupId: GroupID) async throws -> GroupInvite

    /// Accepts an invite. `memberId` claims a specific placeholder — the "Jonas finally joined"
    /// case from §5 — and omitting it joins as somebody new.
    func acceptInvite(
        token: UUID,
        claiming memberId: MemberID?,
        displayName: String?
    ) async throws -> AcceptedInvite
}

extension HTTPSyncTransport: InviteTransport {
    public func createInvite(groupId: GroupID) async throws -> GroupInvite {
        var request = makeAuthorisableRequest(path: "api/v1/groups/\(groupId.rawValue.uuidString.lowercased())/invites")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        return try Self.decodeInvite(try await performAuthorised(request))
    }

    /// Pure, so the one shape that only a real phone ever exercised is testable without a network.
    ///
    /// `expiresAt` is the only `Date` the app decodes from this server, and it arrives as an
    /// ISO-8601 string — .NET's `DateTimeOffset`, microseconds and a numeric offset — while a
    /// default `JSONDecoder` reads a `Date` as a number of seconds. That mismatch meant every
    /// invite failed after the server had already minted and stored the token: the row was there,
    /// the phone said "Något gick fel med inbjudan." Nothing above this line caught it because
    /// every test of the invite flow stubs the transport.
    static func decodeInvite(_ body: Data) throws -> GroupInvite {
        let decoder = JSONDecoder()
        // Not `.iso8601`, which is `ISO8601DateFormatter` with `.withInternetDateTime` only and
        // rejects the fractional seconds this server sends. `ISO8601FormatStyle` takes the
        // fraction, the `Z` and the `+00:00` spellings alike, and is a value type, so it needs no
        // shared mutable formatter to be built once.
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            return try Date(text, strategy: Date.ISO8601FormatStyle())
        }

        do {
            let decoded = try decoder.decode(InviteBody.self, from: body)
            guard let url = URL(string: decoded.url), url.scheme != nil else {
                throw SyncError.malformedResponse("The invite URL was not a URL.")
            }
            return GroupInvite(token: decoded.token, expiresAt: decoded.expiresAt, url: url)
        } catch let error as SyncError {
            throw error
        } catch {
            throw SyncError.malformedResponse(String(describing: error))
        }
    }

    public func acceptInvite(
        token: UUID,
        claiming memberId: MemberID?,
        displayName: String?
    ) async throws -> AcceptedInvite {
        var request = makeAuthorisableRequest(
            path: "api/v1/invites/\(token.uuidString.lowercased())/accept"
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            AcceptBody(memberId: memberId, displayName: displayName)
        )

        let body = try await performAuthorised(request)

        do {
            let decoded = try JSONDecoder().decode(AcceptedBody.self, from: body)
            return AcceptedInvite(groupId: decoded.groupId, memberId: decoded.memberId)
        } catch {
            throw SyncError.malformedResponse(String(describing: error))
        }
    }

    private struct InviteBody: Decodable {
        let token: UUID
        let expiresAt: Date
        let url: String
    }

    private struct AcceptBody: Encodable {
        let memberId: MemberID?
        let displayName: String?
    }

    private struct AcceptedBody: Decodable {
        let groupId: GroupID
        let memberId: MemberID
    }
}
