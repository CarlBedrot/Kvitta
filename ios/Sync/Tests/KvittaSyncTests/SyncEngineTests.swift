import Foundation
import Testing
import KvittaCore
import KvittaCoreTestSupport
import KvittaStorage
@testable import KvittaSync

@Suite("SyncEngine")
@MainActor
struct SyncEngineTests {
    private let members = (1...3).map { Fixtures.member($0) }

    private func makeLedger() throws -> LedgerStore {
        LedgerStore(
            store: try EventStore.inMemory(now: { Fixtures.timestamp }),
            authorId: Fixtures.authorId,
            now: { Fixtures.timestamp }
        )
    }

    /// A group with three members and the design doc's 437.00 kr expense — five queued events.
    @discardableResult
    private func seed(_ ledger: LedgerStore) throws -> GroupID {
        let groupId = Fixtures.groupId
        try ledger.record(
            .groupCreated(GroupCreatedPayload(name: "Fjällresan", currency: .sek)),
            entityId: groupId.rawValue,
            in: groupId
        )
        for (index, memberId) in members.enumerated() {
            try ledger.record(
                .memberAdded(MemberAddedPayload(displayName: "Member \(index + 1)")),
                entityId: memberId.rawValue,
                in: groupId
            )
        }
        try ledger.record(
            .expenseCreated(
                try ExpensePayload.make(
                    description: "Systembolaget",
                    categoryId: "alkohol",
                    date: Fixtures.date,
                    total: Money(amountMinor: 43_700, currency: .sek),
                    paidBy: members[0],
                    splitEquallyAmong: members
                )
            ),
            entityId: Fixtures.expense(1).rawValue,
            in: groupId
        )
        return groupId
    }

    private func makeEngine(
        ledger: LedgerStore,
        transport: StubTransport,
        settings: SyncSettings = .enabled
    ) -> SyncEngine {
        SyncEngine(
            ledger: ledger,
            transport: transport,
            userId: Fixtures.authorId,
            settings: settings,
            pageLimit: 500
        )
    }

    // MARK: - The guarantee that matters

    @Test("With the flag off, nothing is sent and nothing changes")
    func disabledIsATotalNoOp() async throws {
        let ledger = try makeLedger()
        try seed(ledger)
        let before = ledger.state

        let transport = StubTransport()
        let engine = makeEngine(ledger: ledger, transport: transport, settings: .disabled)

        await engine.syncAll()

        #expect(await transport.pushCount == 0)
        #expect(await transport.pullCount == 0)
        #expect(ledger.state == before)
        #expect(try ledger.pendingPushCount() == 5)
        #expect(engine.status == .disabled)
    }

    @Test("An unreachable server changes nothing except the status")
    func offlineIsHarmless() async throws {
        let ledger = try makeLedger()
        try seed(ledger)
        let before = ledger.state

        let transport = StubTransport(behaviour: .fail(.unreachable("connection refused")))
        let engine = makeEngine(ledger: ledger, transport: transport)

        await engine.syncAll()

        // The offline guarantee: the projection is untouched, every event is still queued, and
        // nothing threw. This is the single most important assertion in the package.
        #expect(ledger.state == before)
        #expect(try ledger.pendingPushCount() == 5)
        #expect(ledger.rejectedPushes.isEmpty)
        if case .offline = engine.status {} else {
            Issue.record("Expected an offline status, got \(engine.status)")
        }
    }

    // MARK: - Push

    @Test("A successful push drains the outbox and stamps the sequence numbers")
    func pushDrainsTheOutbox() async throws {
        let ledger = try makeLedger()
        let groupId = try seed(ledger)

        let transport = StubTransport()
        let engine = makeEngine(ledger: ledger, transport: transport)

        await engine.syncAll()

        #expect(try ledger.pendingPushCount() == 0)
        #expect(await transport.pushedEvents.count == 5)
        #expect(ledger.state.groups[groupId]?.lastAppliedSeq == 5)
        // Balances are untouched by syncing — it assigns an order, it does not change the money.
        #expect(ledger.state.groups[groupId]?.balances().amountMinor(for: members[0]) == 29_133)
        #expect(engine.status == .idle)
    }

    @Test("A transient failure keeps events queued and records why")
    func transientFailureKeepsEventsQueued() async throws {
        let ledger = try makeLedger()
        try seed(ledger)

        let transport = StubTransport(behaviour: .fail(.server(status: 500, detail: "boom")))
        let engine = makeEngine(ledger: ledger, transport: transport)

        await engine.syncAll()

        #expect(try ledger.pendingPushCount() == 5)
        #expect(ledger.rejectedPushes.isEmpty)

        // And it drains once the server recovers — nothing was lost in the meantime.
        await transport.set(.acceptAll)
        await engine.syncAll()
        #expect(try ledger.pendingPushCount() == 0)
    }

    @Test("A rejected event leaves the queue, stays visible, and does not block the rest")
    func rejectionsAreParkedNotDropped() async throws {
        let ledger = try makeLedger()
        let groupId = try seed(ledger)

        let queued = try ledger.outboxBatch()
        let doomed = try #require(queued.last)

        let transport = StubTransport(
            behaviour: .reject(eventIds: [doomed.eventId], code: "money_invariant_violated")
        )
        let engine = makeEngine(ledger: ledger, transport: transport)

        await engine.syncAll()

        // The four good events were acknowledged; the refused one is parked, not retried.
        #expect(try ledger.pendingPushCount() == 0)
        #expect(ledger.rejectedPushes.map(\.code) == ["money_invariant_violated"])
        #expect(ledger.rejectedPushes.first?.event.eventId == doomed.eventId)

        // Still in the local log and still counted: the expense really happened on this device.
        #expect(ledger.state.groups[groupId]?.expenses.count == 1)

        // A second sync must not re-send it — that would spin forever.
        let pushesBefore = await transport.pushCount
        await engine.syncAll()
        #expect(await transport.pushCount == pushesBefore)
    }

    @Test("Losing membership is surfaced to a human rather than retried")
    func notAMemberBlocks() async throws {
        let ledger = try makeLedger()
        try seed(ledger)

        let transport = StubTransport(behaviour: .fail(.notAMember))
        let engine = makeEngine(ledger: ledger, transport: transport)

        await engine.syncAll()

        if case .blocked = engine.status {} else {
            Issue.record("Expected a blocked status, got \(engine.status)")
        }
        // Design doc §7: the events are not dropped, they are surfaced.
        #expect(try ledger.pendingPushCount() == 5)
    }

    @Test("An old build is told to upgrade, not left retrying")
    func upgradeRequiredBlocks() async throws {
        let ledger = try makeLedger()
        try seed(ledger)

        let transport = StubTransport(behaviour: .fail(.upgradeRequired("build 41 < 42")))
        let engine = makeEngine(ledger: ledger, transport: transport)

        await engine.syncAll()

        if case .blocked(let message) = engine.status {
            #expect(message.contains("too old"))
        } else {
            Issue.record("Expected a blocked status, got \(engine.status)")
        }
    }

    // MARK: - Pull

    @Test("Pulled events are integrated and the cursor advances")
    func pullIntegratesAndAdvancesTheCursor() async throws {
        let ledger = try makeLedger()
        let groupId = try seed(ledger)

        let transport = StubTransport()
        let engine = makeEngine(ledger: ledger, transport: transport)
        await engine.syncAll() // drain first, so the group exists server-side in the fiction

        // Another member's expense arrives, already numbered by the server.
        var factory = EventFactory()
        let theirs = EventEnvelope(
            groupId: groupId,
            entityId: Fixtures.expense(2).rawValue,
            authorId: UserID(),
            clientTimestamp: Fixtures.timestamp,
            serverSeq: 6,
            payload: .expenseCreated(
                try ExpensePayload.make(
                    description: "Taxi",
                    categoryId: "taxi",
                    date: Fixtures.date,
                    total: Money(amountMinor: 30_000, currency: .sek),
                    paidBy: members[1],
                    splitEquallyAmong: [members[0], members[1]]
                )
            )
        )
        _ = factory

        await transport.enqueuePull(PullResult(events: [theirs], nextCursor: 6))
        await engine.syncAll()

        let group = try #require(ledger.state.groups[groupId])
        #expect(group.expenses.count == 2)
        #expect(group.balances().totalMinor == 0)
        #expect(try ledger.cursor(forGroup: groupId) == 6)
    }

    @Test("Pulling the same page twice changes nothing")
    func pullIsIdempotent() async throws {
        let ledger = try makeLedger()
        let groupId = try seed(ledger)

        let transport = StubTransport()
        let engine = makeEngine(ledger: ledger, transport: transport)
        await engine.syncAll()

        let theirs = EventEnvelope(
            groupId: groupId,
            entityId: Fixtures.member(9).rawValue,
            authorId: UserID(),
            clientTimestamp: Fixtures.timestamp,
            serverSeq: 6,
            payload: .memberAdded(MemberAddedPayload(displayName: "Sent joiner"))
        )

        await transport.enqueuePull(PullResult(events: [theirs], nextCursor: 6))
        await engine.syncAll()
        let afterFirst = ledger.state

        await transport.enqueuePull(PullResult(events: [theirs], nextCursor: 6))
        await engine.syncAll()

        #expect(ledger.state == afterFirst)
    }

    @Test("A device with an empty database discovers its groups and pulls them")
    func reinstalledDeviceRecoversFromTheServer() async throws {
        // Exactly the reinstall case from design doc §6, and the one the unit tests originally
        // could not see: every other test seeds local state first, so iterating local groups
        // looked sufficient. On a real wiped device it pulled nothing at all.
        let ledger = try makeLedger()
        #expect(ledger.state.groups.isEmpty)

        let groupId = Fixtures.groupId
        let transport = StubTransport()
        await transport.setKnownGroups([groupId])

        let history: [EventEnvelope] = [
            EventEnvelope(
                groupId: groupId,
                entityId: groupId.rawValue,
                authorId: Fixtures.authorId,
                clientTimestamp: Fixtures.timestamp,
                serverSeq: 1,
                payload: .groupCreated(GroupCreatedPayload(name: "Fjällresan", currency: .sek))
            ),
            EventEnvelope(
                groupId: groupId,
                entityId: members[0].rawValue,
                authorId: Fixtures.authorId,
                clientTimestamp: Fixtures.timestamp,
                serverSeq: 2,
                payload: .memberAdded(MemberAddedPayload(displayName: "Carl"))
            )
        ]

        await transport.enqueuePull(PullResult(events: history, nextCursor: 2))

        let engine = makeEngine(ledger: ledger, transport: transport)
        await engine.syncAll()

        #expect(ledger.state.groups[groupId]?.name == "Fjällresan")
        #expect(try ledger.cursor(forGroup: groupId) == 2)
    }

    @Test("Scheduling a sync coalesces a burst of saves into one push")
    func scheduleSyncIsDebounced() async throws {
        let ledger = try makeLedger()
        try seed(ledger)

        let transport = StubTransport()
        let engine = makeEngine(ledger: ledger, transport: transport)

        for _ in 0..<5 {
            engine.scheduleSync(after: .milliseconds(40))
        }

        try await Task.sleep(for: .milliseconds(400))

        // Five saves, one round trip.
        #expect(await transport.pushCount == 1)
        #expect(try ledger.pendingPushCount() == 0)
    }
}
