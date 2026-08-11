import Foundation
import Testing
import KvittaCore
@testable import KvittaSync

/// Decoding the invite endpoint's response, from the bytes the server actually sends.
///
/// The fixture is copied verbatim off the wire on 2026-08-11 — `.NET` writes a `DateTimeOffset`
/// as an ISO-8601 string with microsecond precision and a numeric offset, and Swift's default
/// `JSONDecoder` reads a `Date` as a number of seconds. Every invite ever created failed on that
/// mismatch: the server minted the token and stored the row, and the app threw the response away
/// and said "Något gick fel med inbjudan." Only a real device ever exercised this path, because
/// every test above it stubs the transport.
@Suite("Invite response decoding")
struct InviteDecodingTests {

    /// Byte-for-byte what `POST /api/v1/groups/{id}/invites` returned.
    private let fixture = """
        {"token":"922dcfcd-7014-4197-8244-5cedf210786b",\
        "expiresAt":"2026-08-25T16:28:51.162013+00:00",\
        "url":"slice://invite/922dcfcd-7014-4197-8244-5cedf210786b"}
        """

    @Test("The server's own response decodes")
    func decodesTheServerShape() throws {
        let invite = try HTTPSyncTransport.decodeInvite(Data(fixture.utf8))

        #expect(invite.token == UUID(uuidString: "922dcfcd-7014-4197-8244-5cedf210786b"))
        #expect(invite.url.absoluteString == "slice://invite/922dcfcd-7014-4197-8244-5cedf210786b")
        // 2026-08-25T16:28:51Z. Compared as an instant rather than a formatted string so the
        // assertion does not depend on the machine's time zone.
        #expect(abs(invite.expiresAt.timeIntervalSince1970 - 1_787_675_331.162) < 0.01)
    }

    /// The offset and the fractional part are both things a server is free to change without
    /// telling anyone, so all four spellings have to survive.
    @Test("Every ISO-8601 spelling of the same instant is accepted", arguments: [
        "2026-08-25T16:28:51.162013+00:00",
        "2026-08-25T16:28:51+00:00",
        "2026-08-25T16:28:51.162Z",
        "2026-08-25T16:28:51Z",
    ])
    func acceptsTheSpellings(timestamp: String) throws {
        let body = """
            {"token":"922dcfcd-7014-4197-8244-5cedf210786b",\
            "expiresAt":"\(timestamp)",\
            "url":"slice://invite/922dcfcd-7014-4197-8244-5cedf210786b"}
            """

        let invite = try HTTPSyncTransport.decodeInvite(Data(body.utf8))

        #expect(Int(invite.expiresAt.timeIntervalSince1970) == 1_787_675_331)
    }

    @Test("A response that is not JSON is a malformed response, not a crash")
    func refusesGarbage() {
        #expect(throws: SyncError.self) {
            try HTTPSyncTransport.decodeInvite(Data("not json".utf8))
        }
    }

    @Test("A url the phone cannot open is refused rather than carried around broken")
    func refusesABrokenURL() {
        let body = """
            {"token":"922dcfcd-7014-4197-8244-5cedf210786b",\
            "expiresAt":"2026-08-25T16:28:51Z",\
            "url":""}
            """

        #expect(throws: SyncError.self) {
            try HTTPSyncTransport.decodeInvite(Data(body.utf8))
        }
    }
}
