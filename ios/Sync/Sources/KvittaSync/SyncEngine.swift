import Foundation
import KvittaCore
import KvittaStorage

/// What the UI shows about syncing. Never blocks anything.
public enum SyncStatus: Hashable, Sendable {
    case disabled
    case idle
    case syncing
    /// Retryable — offline, timeout, a 500. Normal, and not worth alarming anyone about.
    case offline(String)
    /// Needs a human: membership revoked, or the build is too old (design doc §7, §9).
    case blocked(String)
}

/// Drives the outbox and the pull loop.
///
/// The contract this type exists to keep: **the app works identically whether this runs, is
/// switched off, or cannot reach anything.** Nothing here throws into the UI, nothing here blocks
/// a save, and no local event is ever dropped. Sync is something that happens to the log later,
/// not something the log depends on.
@MainActor
@Observable
public final class SyncEngine {
    public private(set) var status: SyncStatus = .disabled
    public private(set) var lastSyncedAt: Timestamp?

    private let ledger: LedgerStore
    private let transport: any SyncTransport
    private let userId: UserID
    private let settings: SyncSettings
    private let pageLimit: Int

    private var inFlight = false
    private var debounceTask: Task<Void, Never>?

    public init(
        ledger: LedgerStore,
        transport: any SyncTransport,
        userId: UserID,
        settings: SyncSettings = .standard,
        pageLimit: Int = 500
    ) {
        self.ledger = ledger
        self.transport = transport
        self.userId = userId
        self.settings = settings
        self.pageLimit = pageLimit
        self.status = settings.isEnabled ? .idle : .disabled
    }

    public var isEnabled: Bool { settings.isEnabled }

    // MARK: - Triggers (design doc §6)

    /// App foreground, and the pull-to-refresh gesture. Pushes first so this device's work is
    /// ordered before whatever it is about to learn.
    public func syncAll() async {
        guard settings.isEnabled, !inFlight else { return }
        inFlight = true
        defer { inFlight = false }

        status = .syncing

        var outcome: SyncStatus = .idle
        if let failure = await pushOutbox() {
            outcome = failure
        }

        // Local groups alone are not enough. A reinstalled device has none, so iterating only
        // what it already knows would leave it showing an empty app forever while its whole
        // history sat on the server — design doc §6's "new device / reinstall" case. Ask the
        // server too, and pull the union.
        var groupIds = Set(ledger.state.groups.keys)
        do {
            groupIds.formUnion(try await transport.groups(as: userId))
        } catch let error as SyncError {
            // Discovery failing is not fatal: fall back to the groups we know about locally.
            outcome = status(for: error)
        } catch {
            outcome = .offline(String(describing: error))
        }

        for groupId in groupIds.sorted() {
            if let failure = await pull(groupId: groupId) {
                outcome = failure
            }
        }

        if case .idle = outcome {
            lastSyncedAt = Timestamp(Date())
        }

        status = outcome
    }

    /// Called after a local mutation. Debounced, because saving four expenses in a row should be
    /// one push, and because a save must never wait on a network call.
    public func scheduleSync(after delay: Duration = .seconds(3)) {
        guard settings.isEnabled else { return }

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.syncAll()
        }
    }

    // MARK: - The two halves

    /// Drains the outbox. Returns a status if something went wrong, nil on success.
    @discardableResult
    func pushOutbox() async -> SyncStatus? {
        guard settings.isEnabled else { return nil }

        while true {
            let batch: [EventEnvelope]
            do {
                batch = try ledger.outboxBatch(limit: pageLimit)
            } catch {
                return .offline(String(describing: error))
            }

            guard !batch.isEmpty else { return nil }

            // One group at a time: the endpoint is per-group, and events for different groups
            // must not be mixed into one request.
            let groupId = batch[0].groupId
            let forGroup = batch.filter { $0.groupId == groupId }

            do {
                let result = try await transport.push(groupId: groupId, events: forGroup, as: userId)

                if !result.accepted.isEmpty {
                    try ledger.acknowledge(
                        result.accepted.map { (eventId: $0.eventId, serverSeq: $0.serverSeq) }
                    )
                }

                if !result.rejected.isEmpty {
                    // Out of the retry queue, into the "these could not sync" list. Never dropped.
                    try ledger.markRejected(
                        result.rejected.map { (eventId: $0.eventId, code: $0.code) }
                    )
                }

                // Nothing moved and nothing was refused: stop rather than loop forever.
                if result.accepted.isEmpty && result.rejected.isEmpty {
                    return nil
                }
            } catch let error as SyncError {
                recordFailure(for: forGroup, error: error)
                return status(for: error)
            } catch {
                return .offline(String(describing: error))
            }
        }
    }

    /// Pulls one group to exhaustion, advancing the cursor as it goes.
    @discardableResult
    func pull(groupId: GroupID) async -> SyncStatus? {
        guard settings.isEnabled else { return nil }

        do {
            var cursor = try ledger.cursor(forGroup: groupId)

            while true {
                let page = try await transport.pull(
                    groupId: groupId,
                    after: cursor,
                    limit: pageLimit,
                    as: userId
                )

                guard !page.events.isEmpty else { return nil }

                // `integrate` appends and rebuilds, so pulled events land in serverSeq order with
                // any still-unacknowledged local events replayed last — design doc §6's rule,
                // which Storage already implements.
                try ledger.integrate(page.events)

                cursor = page.nextCursor
                try ledger.setCursor(cursor, forGroup: groupId)

                if page.events.count < pageLimit { return nil }
            }
        } catch let error as SyncError {
            return status(for: error)
        } catch {
            return .offline(String(describing: error))
        }
    }

    // MARK: - Failure handling

    private func recordFailure(for events: [EventEnvelope], error: SyncError) {
        guard error.isRetryable else { return }
        // Keep the events queued and remember why. CLAUDE.md: never drop outbox events silently.
        try? ledger.recordPushFailure(events.map(\.eventId), error: String(describing: error))
    }

    private func status(for error: SyncError) -> SyncStatus {
        switch error {
        case .unreachable(let detail), .server(_, let detail):
            return .offline(detail)
        case .notAMember:
            return .blocked("You are no longer a member of this group.")
        case .upgradeRequired:
            return .blocked("This version of Kvitta is too old to sync. Please update.")
        case .malformedResponse(let detail):
            return .blocked(detail)
        }
    }
}
