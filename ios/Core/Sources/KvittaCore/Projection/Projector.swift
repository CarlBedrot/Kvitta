import Foundation

/// Folds events into state. Pure: `(state, event) -> state`, no IO, no clock, no randomness.
///
/// Two properties hold everything else up:
///
/// - **It never throws and never crashes.** An event it cannot apply is recorded in
///   `LedgerState.skipped` and skipped. A log is replayed on a phone in a tunnel; there is no
///   useful error to surface mid-fold and nothing to be gained by refusing to show the other 400
///   expenses.
/// - **It is idempotent per `eventId`.** Applying the same event twice is a no-op, which is what
///   makes push-then-pull-back safe and is exactly property test P3.
public enum Projector {

    /// Folds one event into a copy of `state`.
    ///
    /// Costs one copy of the group's tables per call, which is the honest price of a value-in,
    /// value-out signature. Folding a whole log through this would be quadratic, so `replay` does
    /// not — it uses the same logic in place. Reach for `replay` for anything longer than a
    /// handful of events.
    public static func apply(_ state: LedgerState, _ event: EventEnvelope) -> LedgerState {
        var next = state
        applyInPlace(&next, event)
        return next
    }

    /// The fold, written as a mutation so a replay stays linear.
    ///
    /// Same semantics as `apply` — same skips, same results, no IO — but because `state` is
    /// `inout` and the group is lifted out of the dictionary with `removeValue`, every edit below
    /// touches a uniquely-referenced buffer and mutates in place. Folding a log through the
    /// value-returning form instead copies the group's whole expense table once per event, which
    /// is quadratic in the length of the log.
    ///
    /// Measured: 4.5 µs per event, flat from 1 000 to 5 000 events — a heavy group replays in
    /// ~22 ms. See `ReplayPerformanceTests`, and run it in release.
    static func applyInPlace(_ state: inout LedgerState, _ event: EventEnvelope) {
        // Idempotency first, before anything is inspected: a repeat must not even be able to
        // append a duplicate skip record.
        guard state.appliedEventIds.insert(event.eventId).inserted else { return }

        if case .groupCreated(let payload) = event.payload {
            if var existing = state.groups.removeValue(forKey: event.groupId) {
                // Seen, not applied — the watermark still moves, as on every other skip path.
                existing.lastAppliedSeq = advance(existing.lastAppliedSeq, with: event.serverSeq)
                state.groups[event.groupId] = existing
                recordSkip(&state, event, .groupAlreadyExists)
                return
            }
            var group = GroupState(
                id: event.groupId,
                name: payload.name,
                currency: payload.currency
            )
            group.lastAppliedSeq = event.serverSeq
            state.groups[event.groupId] = group
            return
        }

        // Lifting the group out of the dictionary rather than reading a copy of it is the whole
        // trick: `group` now holds the only reference to its members/expenses/payments tables, so
        // the edits below are in-place instead of copy-on-write. It goes back at every exit.
        guard var group = state.groups.removeValue(forKey: event.groupId) else {
            recordSkip(&state, event, .unknownGroup)
            return
        }

        var skipReason: SkipReason?

        switch event.payload {
        case .groupCreated:
            skipReason = .groupAlreadyExists // handled above; unreachable

        case .groupUpdated(let payload):
            if let name = payload.name { group.name = name }
            if let currency = payload.currency {
                // Only while the ledger is empty. The primary currency decides how existing
                // amounts are read and defaulted; changing it under a live ledger would
                // reinterpret every stored number (Payloads.swift already warns). Ignored, not
                // skipped: the rest of the update (a rename, say) still applies.
                if group.expenses.isEmpty && group.payments.isEmpty {
                    group.currency = currency
                }
            }
            if let coverPhotoRef = payload.coverPhotoRef { group.coverPhotoRef = coverPhotoRef }
            if let description = payload.description {
                // Empty clears; anything else replaces. Stored trimmed-as-sent — the UI trims.
                group.about = description.isEmpty ? nil : description
            }

        case .memberAdded(let payload):
            let memberId = event.memberId
            guard group.members[memberId] == nil else {
                skipReason = .memberAlreadyExists(memberId)
                break
            }
            group.members[memberId] = Member(
                id: memberId,
                displayName: payload.displayName,
                linkedUserId: payload.linkedUserId
            )

        case .memberUpdated(let payload):
            let memberId = event.memberId
            guard group.members[memberId] != nil else {
                skipReason = .unknownMember(memberId)
                break
            }
            // Absent means unchanged. Note that nothing about money moves here: a member's
            // identity and their balance are independent, which is what lets someone join a group
            // months late and inherit a history that already adds up.
            if let displayName = payload.displayName {
                group.members[memberId]?.displayName = displayName
            }
            if let linkedUserId = payload.linkedUserId {
                group.members[memberId]?.linkedUserId = linkedUserId
            }

        case .memberRemoved:
            let memberId = event.memberId
            guard group.members[memberId] != nil else {
                skipReason = .unknownMember(memberId)
                break
            }
            // Deactivated, not deleted: their balance and history stay visible.
            group.members[memberId]?.isActive = false

        case .expenseCreated(let payload):
            let expenseId = event.expenseId
            guard group.expenses[expenseId] == nil else {
                skipReason = .entityAlreadyExists
                break
            }
            if let unknown = firstUnknownMember(payload.involvedMembers, in: group) {
                skipReason = .unknownMember(unknown)
                break
            }
            group.expenses[expenseId] = Expense(
                id: expenseId,
                payload: payload,
                createdBy: event.authorId,
                createdAt: event.clientTimestamp,
                lastModifiedBy: event.authorId,
                lastModifiedAt: event.clientTimestamp
            )

        case .expenseUpdated(let payload):
            let expenseId = event.expenseId
            guard group.expenses[expenseId] != nil else {
                skipReason = .unknownExpense(expenseId)
                break
            }
            if let unknown = firstUnknownMember(payload.involvedMembers, in: group) {
                skipReason = .unknownMember(unknown)
                break
            }
            // Full replacement, not a merge. Last event in serverSeq order wins entirely
            // (design doc §2); the previous version survives in the log as history.
            group.expenses[expenseId]?.payload = payload
            group.expenses[expenseId]?.lastModifiedBy = event.authorId
            group.expenses[expenseId]?.lastModifiedAt = event.clientTimestamp
            group.expenses[expenseId]?.revision += 1

        case .expenseDeleted:
            let expenseId = event.expenseId
            guard group.expenses[expenseId] != nil else {
                skipReason = .unknownExpense(expenseId)
                break
            }
            group.expenses[expenseId]?.isDeleted = true

        case .expenseRestored:
            let expenseId = event.expenseId
            guard group.expenses[expenseId] != nil else {
                skipReason = .unknownExpense(expenseId)
                break
            }
            group.expenses[expenseId]?.isDeleted = false

        case .paymentRecorded(let payload):
            let paymentId = event.paymentId
            guard group.payments[paymentId] == nil else {
                skipReason = .entityAlreadyExists
                break
            }
            if let unknown = firstUnknownMember(
                [payload.fromMemberId, payload.toMemberId],
                in: group
            ) {
                skipReason = .unknownMember(unknown)
                break
            }
            // Born pending only when there is somebody who could ever confirm it: a payee with
            // a linked account, who is not the author. The payee recording their own incoming
            // payment is its own confirmation, and a placeholder payee has no one to ask — that
            // is the by-name friend who never installs the app, whose cash payments must keep
            // working exactly as before M8.
            let payeeUser = group.members[payload.toMemberId]?.linkedUserId
            let born: PaymentStatus =
                (payeeUser == nil || payeeUser == event.authorId) ? .confirmed : .pending
            group.payments[paymentId] = Payment(
                id: paymentId,
                payload: payload,
                recordedBy: event.authorId,
                recordedAt: event.clientTimestamp,
                status: born
            )

        case .paymentConfirmed, .paymentDisputed:
            let paymentId = event.paymentId
            guard let payment = group.payments[paymentId] else {
                skipReason = .unknownPayment(paymentId)
                break
            }
            // Only the payee's word moves the state — this guard, replayed identically on every
            // device, is the actual security boundary. A forged confirmation from anyone else is
            // skipped everywhere, so it moves no money no matter what the server stored.
            guard let payeeUser = group.members[payment.toMemberId]?.linkedUserId,
                  payeeUser == event.authorId else {
                skipReason = .notThePayee(paymentId)
                break
            }
            // Last event wins, like every correction in the log: a payee who disputed and then
            // found the money can still confirm, and the other way around.
            group.payments[paymentId]?.status =
                event.payload.eventType == EventType.paymentConfirmed ? .confirmed : .disputed

        case .unknown(let type, _):
            skipReason = .unknownEventType(type)
        }

        // A skipped event has still been seen, so the watermark moves either way. Otherwise an
        // unknown event type at the head of a page would pin the cursor and re-deliver forever.
        group.lastAppliedSeq = Projector.advance(group.lastAppliedSeq, with: event.serverSeq)
        state.groups[event.groupId] = group

        if let skipReason {
            recordSkip(&state, event, skipReason)
        }
    }

    private static func recordSkip(
        _ state: inout LedgerState,
        _ event: EventEnvelope,
        _ reason: SkipReason
    ) {
        state.skipped.append(
            SkippedEvent(
                eventId: event.eventId,
                groupId: event.groupId,
                type: event.type,
                reason: reason
            )
        )
    }

    // MARK: - Replay

    /// Folds a sequence in the order given. The caller is responsible for that order — use
    /// `replay(synced:pending:)` unless you already know the events are ordered.
    public static func replay(
        _ events: [EventEnvelope],
        into initial: LedgerState = .empty
    ) -> LedgerState {
        // Deliberately not `events.reduce(initial, apply)`. That copies the whole projection once
        // per event, which is quadratic in the length of the log.
        var state = initial
        for event in events {
            applyInPlace(&state, event)
        }
        return state
    }

    /// Replays acknowledged events in `serverSeq` order, then unacknowledged local events last.
    ///
    /// This is design doc §6's ordering rule. When a pull delivers other members' events that
    /// interleave before your unpushed ones, the answer is to rebuild in this order rather than
    /// to patch cleverly — at a few thousand events that costs microseconds.
    public static func replay(
        synced: [EventEnvelope],
        pending: [EventEnvelope],
        into initial: LedgerState = .empty
    ) -> LedgerState {
        replay(EventEnvelope.sortedForReplay(synced: synced, pending: pending), into: initial)
    }

    // MARK: - Helpers

    /// Members must be added before they can be referenced. A local event can never break that,
    /// and a synced one arrives in `serverSeq` order, so an unknown member here means genuinely
    /// broken data — safer to skip the whole expense than to invent a member with no name.
    private static func firstUnknownMember<S: Sequence>(
        _ memberIds: S,
        in group: GroupState
    ) -> MemberID? where S.Element == MemberID {
        memberIds.sorted().first { group.members[$0] == nil }
    }

    private static func advance(_ current: Int64?, with incoming: Int64?) -> Int64? {
        guard let incoming else { return current }
        guard let current else { return incoming }
        return Swift.max(current, incoming)
    }
}
