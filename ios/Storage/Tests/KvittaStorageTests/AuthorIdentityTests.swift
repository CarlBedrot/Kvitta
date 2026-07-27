import Foundation
import Testing
import KvittaCore
import KvittaCoreTestSupport
@testable import KvittaStorage

/// Changing who new events are authored by, which is what signing in does.
@Suite("Author identity")
@MainActor
struct AuthorIdentityTests {
    private let signedIn = UserID(uuidString: "00000000-0000-0000-00cc-000000000001")!

    /// Returns the event store alongside the ledger, so a test can read the log back directly
    /// rather than the ledger needing a hatch that exists only for tests.
    private func makeStore() throws -> (LedgerStore, EventStore) {
        let store = try EventStore.inMemory(now: { Fixtures.timestamp })
        let ledger = LedgerStore(store: store, authorId: Fixtures.authorId, now: { Fixtures.timestamp })
        return (ledger, store)
    }

    @Test("New events carry the new author")
    func setAuthorAffectsSubsequentWrites() throws {
        let (ledger, store) = try makeStore()

        ledger.setAuthor(signedIn)
        let event = try ledger.record(
            .groupCreated(GroupCreatedPayload(name: "Efter inloggning", currency: .sek)),
            entityId: Fixtures.groupId.rawValue,
            in: Fixtures.groupId
        )

        #expect(event.authorId == signedIn)
        #expect(ledger.currentAuthorId == signedIn)
    }

    @Test("Events already written keep the author they were written with")
    func setAuthorRewritesNothing() throws {
        // Events are immutable (CLAUDE.md). Signing in is not a licence to rewrite history, and
        // this is exactly why a group created before signing in cannot simply be adopted
        // afterwards — its member is still linked to the old device identity.
        let (ledger, store) = try makeStore()

        let before = try ledger.record(
            .groupCreated(GroupCreatedPayload(name: "Före inloggning", currency: .sek)),
            entityId: Fixtures.groupId.rawValue,
            in: Fixtures.groupId
        )

        ledger.setAuthor(signedIn)
        try ledger.rebuild()

        let stored = try #require(
            try store.allEvents().events.first { $0.eventId == before.eventId }
        )
        #expect(stored.authorId == Fixtures.authorId)
    }

    @Test("Changing identity does not disturb the projection")
    func setAuthorLeavesStateAlone() throws {
        let (ledger, store) = try makeStore()
        try ledger.record(
            .groupCreated(GroupCreatedPayload(name: "Fjällresan", currency: .sek)),
            entityId: Fixtures.groupId.rawValue,
            in: Fixtures.groupId
        )

        let before = ledger.state.groups[Fixtures.groupId]?.name
        ledger.setAuthor(signedIn)

        #expect(ledger.state.groups[Fixtures.groupId]?.name == before)
    }
}
