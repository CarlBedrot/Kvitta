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

    public static func apply(_ state: LedgerState, _ event: EventEnvelope) -> LedgerState {
        // Idempotency first, before anything is inspected: a repeat must not even be able to
        // append a duplicate skip record.
        guard !state.appliedEventIds.contains(event.eventId) else { return state }

        var next = state
        next.appliedEventIds.insert(event.eventId)

        func skip(_ reason: SkipReason) -> LedgerState {
            var skipped = next
            skipped.skipped.append(
                SkippedEvent(
                    eventId: event.eventId,
                    groupId: event.groupId,
                    type: event.type,
                    reason: reason
                )
            )
            // A skipped event has still been seen, so the watermark moves. Otherwise an unknown
            // event type at the head of a page would pin the cursor and re-deliver forever.
            if var group = skipped.groups[event.groupId] {
                group.lastAppliedSeq = Projector.advance(group.lastAppliedSeq, with: event.serverSeq)
                skipped.groups[event.groupId] = group
            }
            return skipped
        }

        if case .groupCreated(let payload) = event.payload {
            guard next.groups[event.groupId] == nil else { return skip(.groupAlreadyExists) }
            var group = GroupState(
                id: event.groupId,
                name: payload.name,
                currency: payload.currency
            )
            group.lastAppliedSeq = event.serverSeq
            next.groups[event.groupId] = group
            return next
        }

        guard var group = next.groups[event.groupId] else { return skip(.unknownGroup) }

        switch event.payload {
        case .groupCreated:
            return skip(.groupAlreadyExists) // handled above; unreachable

        case .groupUpdated(let payload):
            if let name = payload.name { group.name = name }
            if let currency = payload.currency { group.currency = currency }
            if let coverPhotoRef = payload.coverPhotoRef { group.coverPhotoRef = coverPhotoRef }

        case .memberAdded(let payload):
            let memberId = event.memberId
            guard group.members[memberId] == nil else {
                return skip(.memberAlreadyExists(memberId))
            }
            group.members[memberId] = Member(
                id: memberId,
                displayName: payload.displayName,
                linkedUserId: payload.linkedUserId
            )

        case .memberRemoved:
            let memberId = event.memberId
            guard var member = group.members[memberId] else {
                return skip(.unknownMember(memberId))
            }
            // Deactivated, not deleted: their balance and history stay visible.
            member.isActive = false
            group.members[memberId] = member

        case .expenseCreated(let payload):
            let expenseId = event.expenseId
            guard group.expenses[expenseId] == nil else { return skip(.entityAlreadyExists) }
            guard payload.currency == group.currency else {
                return skip(.currencyMismatch(expected: group.currency, found: payload.currency))
            }
            if let unknown = firstUnknownMember(payload.involvedMembers, in: group) {
                return skip(.unknownMember(unknown))
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
            guard var expense = group.expenses[expenseId] else {
                return skip(.unknownExpense(expenseId))
            }
            guard payload.currency == group.currency else {
                return skip(.currencyMismatch(expected: group.currency, found: payload.currency))
            }
            if let unknown = firstUnknownMember(payload.involvedMembers, in: group) {
                return skip(.unknownMember(unknown))
            }
            // Full replacement, not a merge. Last event in serverSeq order wins entirely
            // (design doc §2); the previous version survives in the log as history.
            expense.payload = payload
            expense.lastModifiedBy = event.authorId
            expense.lastModifiedAt = event.clientTimestamp
            expense.revision += 1
            group.expenses[expenseId] = expense

        case .expenseDeleted:
            let expenseId = event.expenseId
            guard var expense = group.expenses[expenseId] else {
                return skip(.unknownExpense(expenseId))
            }
            expense.isDeleted = true
            group.expenses[expenseId] = expense

        case .expenseRestored:
            let expenseId = event.expenseId
            guard var expense = group.expenses[expenseId] else {
                return skip(.unknownExpense(expenseId))
            }
            expense.isDeleted = false
            group.expenses[expenseId] = expense

        case .paymentRecorded(let payload):
            let paymentId = event.paymentId
            guard group.payments[paymentId] == nil else { return skip(.entityAlreadyExists) }
            guard payload.currency == group.currency else {
                return skip(.currencyMismatch(expected: group.currency, found: payload.currency))
            }
            if let unknown = firstUnknownMember(
                [payload.fromMemberId, payload.toMemberId],
                in: group
            ) {
                return skip(.unknownMember(unknown))
            }
            group.payments[paymentId] = Payment(
                id: paymentId,
                payload: payload,
                recordedBy: event.authorId,
                recordedAt: event.clientTimestamp
            )

        case .unknown(let type, _):
            return skip(.unknownEventType(type))
        }

        group.lastAppliedSeq = Projector.advance(group.lastAppliedSeq, with: event.serverSeq)
        next.groups[event.groupId] = group
        return next
    }

    // MARK: - Replay

    /// Folds a sequence in the order given. The caller is responsible for that order — use
    /// `replay(synced:pending:)` unless you already know the events are ordered.
    public static func replay(
        _ events: [EventEnvelope],
        into initial: LedgerState = .empty
    ) -> LedgerState {
        events.reduce(initial, apply)
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
