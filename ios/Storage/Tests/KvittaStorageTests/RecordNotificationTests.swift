import Foundation
import Testing
import KvittaCore
import KvittaCoreTestSupport
@testable import KvittaStorage

/// `record` announces local writes so something can push them.
///
/// The app shipped with `SyncEngine.scheduleSync` implemented, unit-tested and called from
/// nowhere. Saving an expense left it in the outbox until the app was next foregrounded, which
/// looks like sync being unreliable rather than like a missing line of wiring. These tests exist
/// so the hook cannot go quiet again without something turning red.
@Suite("Local writes announce themselves")
@MainActor
struct RecordNotificationTests {
    private func makeStore() throws -> LedgerStore {
        LedgerStore(
            store: try EventStore.inMemory(now: { Fixtures.timestamp }),
            authorId: Fixtures.authorId,
            now: { Fixtures.timestamp }
        )
    }

    private func createGroup(_ ledger: LedgerStore) throws {
        try ledger.record(
            .groupCreated(GroupCreatedPayload(name: "Fjällresan", currency: .sek)),
            entityId: Fixtures.groupId.rawValue,
            in: Fixtures.groupId
        )
    }

    @Test("Recording a local event fires the hook")
    func recordFires() throws {
        let ledger = try makeStore()
        var fired = 0
        ledger.onRecord = { fired += 1 }

        try createGroup(ledger)

        #expect(fired == 1)
    }

    @Test("Every local write fires it, so no save site can be forgotten")
    func everyWriteFires() throws {
        let ledger = try makeStore()
        var fired = 0
        ledger.onRecord = { fired += 1 }

        try createGroup(ledger)
        for index in 1...3 {
            try ledger.record(
                .memberAdded(MemberAddedPayload(displayName: "Member \(index)")),
                entityId: Fixtures.member(index).rawValue,
                in: Fixtures.groupId
            )
        }

        #expect(fired == 4)
    }

    // There is deliberately no test that a *failed* append leaves the hook unfired. `EventStore`
    // is a concrete struct with no protocol seam, so proving it would mean introducing an
    // abstraction for the sole benefit of the test. The guarantee is instead held by where the
    // call sits: `onRecord` is the line after `store.append` throws or does not.

    @Test("Events pulled from the server do not fire it")
    func integrateDoesNotFire() throws {
        let ledger = try makeStore()
        var fired = 0
        ledger.onRecord = { fired += 1 }

        // Pushing these back would be a loop: they arrived from the server in the first place.
        try ledger.integrate([
            EventEnvelope(
                groupId: Fixtures.groupId,
                entityId: Fixtures.groupId.rawValue,
                authorId: Fixtures.authorId,
                clientTimestamp: Fixtures.timestamp,
                serverSeq: 1,
                payload: .groupCreated(GroupCreatedPayload(name: "Fjällresan", currency: .sek))
            )
        ])

        #expect(fired == 0)
    }
}
