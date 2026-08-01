import Foundation
import KvittaCore
@testable import KvittaSync

/// A server that does whatever the test tells it to, instantly.
///
/// Everything worth knowing about the engine is about what it does with the *answers* — draining
/// an outbox, parking rejections, leaving the log intact when nothing answers at all — so the
/// answers are the thing to control. No URLSession, no localhost, no waiting.
actor StubTransport: SyncTransport {
    enum Behaviour: Sendable {
        /// Accept everything, assigning sequence numbers from `nextSeq` upward.
        case acceptAll
        /// Accept everything except these, which are refused with the given code.
        case reject(eventIds: Set<EventID>, code: String)
        case fail(SyncError)
    }

    private(set) var behaviour: Behaviour
    private(set) var pushCount = 0
    private(set) var pullCount = 0
    private(set) var pushedEvents: [EventEnvelope] = []
    private var nextSeq: Int64 = 1

    /// Pages the stub will hand back on pull, in order, per group — pulls run concurrently now,
    /// so a single shared queue would hand group A's history to whichever pull asked first.
    private var pullPages: [GroupID: [PullResult]] = [:]

    /// Groups whose pulls fail with a 500 while everything else works — for asserting that one
    /// bad group never blocks the rest.
    private var failingPulls: Set<GroupID> = []

    /// Groups the "server" believes this user is in, for the reinstall case.
    private var knownGroups: [GroupID] = []
    private(set) var groupsCount = 0

    init(behaviour: Behaviour = .acceptAll) {
        self.behaviour = behaviour
    }

    func set(_ behaviour: Behaviour) {
        self.behaviour = behaviour
    }

    func enqueuePull(_ page: PullResult, for groupId: GroupID) {
        pullPages[groupId, default: []].append(page)
    }

    func setFailingPulls(_ groups: Set<GroupID>) {
        failingPulls = groups
    }

    func setKnownGroups(_ groups: [GroupID]) {
        knownGroups = groups
    }

    func groups(as userId: UserID) async throws -> [GroupID] {
        groupsCount += 1

        if case .fail(let error) = behaviour {
            throw error
        }

        return knownGroups
    }

    func push(
        groupId: GroupID,
        events: [EventEnvelope],
        as userId: UserID
    ) async throws -> PushResult {
        pushCount += 1

        if case .fail(let error) = behaviour {
            throw error
        }

        pushedEvents.append(contentsOf: events)

        var accepted: [PushResult.Acknowledgement] = []
        var rejected: [PushResult.Rejection] = []

        for event in events {
            if case .reject(let ids, let code) = behaviour, ids.contains(event.eventId) {
                rejected.append(
                    PushResult.Rejection(eventId: event.eventId, code: code, reason: "stubbed")
                )
                continue
            }

            accepted.append(
                PushResult.Acknowledgement(eventId: event.eventId, serverSeq: nextSeq)
            )
            nextSeq += 1
        }

        return PushResult(accepted: accepted, rejected: rejected)
    }

    func pull(
        groupId: GroupID,
        after cursor: Int64,
        limit: Int,
        as userId: UserID
    ) async throws -> PullResult {
        pullCount += 1

        if case .fail(let error) = behaviour {
            throw error
        }

        if failingPulls.contains(groupId) {
            throw SyncError.server(status: 500, detail: "stubbed pull failure")
        }

        guard var pages = pullPages[groupId], !pages.isEmpty else {
            return PullResult(events: [], nextCursor: cursor)
        }

        let page = pages.removeFirst()
        pullPages[groupId] = pages
        return page
    }
}
