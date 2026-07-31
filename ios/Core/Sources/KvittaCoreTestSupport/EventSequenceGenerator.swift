import Foundation
import KvittaCore

public struct GeneratedHistory {
    public let seed: UInt64
    public let groupId: GroupID
    /// The group's primary currency. Since M7 a history can also contain events in
    /// `otherCurrencies` — a group is a container of per-currency ledgers.
    public let currency: CurrencyCode
    /// The extra currencies this history's expenses and payments may use. Empty for a
    /// single-currency history; the generator emits both kinds.
    public let otherCurrencies: [CurrencyCode]
    public let memberIds: [MemberID]
    public let events: [EventEnvelope]
    public var nextServerSeq: Int64
}

/// Produces a plausible group history from a seed: people joining and leaving, expenses in every
/// split mode, edits, deletions, restores, settle-ups, and the occasional event from a build that
/// does not exist yet.
///
/// Everything it emits is *valid* — the point of the property tests is not that the projector
/// rejects garbage, it is that a legitimate sequence of events, in any order and combination,
/// still leaves the books balanced.
public enum EventSequenceGenerator {

    public static func make(seed: UInt64, maxActions: Int = 60) throws -> GeneratedHistory {
        var rng = SeededRandom(seed: seed)

        let groupId = GroupID(rawValue: rng.nextUUID())
        let authorId = UserID(rawValue: rng.nextUUID())
        let currency = rng.pick([CurrencyCode.sek, .dkk, .nok])
        // Roughly half the histories are mixed-currency (M7). The property tests must hold over
        // both shapes — a single-currency group is still the common case, not a legacy one.
        let otherCurrencies: [CurrencyCode] = rng.nextInt(in: 1...100) <= 50
            ? [rng.pick([CurrencyCode.sek, .dkk, .nok, .eur].filter { $0 != currency })]
            : []
        // Each money event rolls its own currency: mostly the primary, sometimes the other.
        func eventCurrency(_ rng: inout SeededRandom) -> CurrencyCode {
            guard let other = otherCurrencies.first, rng.nextInt(in: 1...100) <= 35 else {
                return currency
            }
            return other
        }

        var events: [EventEnvelope] = []
        var seq: Int64 = 0

        // Takes the event id rather than drawing one, so this nested function never captures the
        // generator — otherwise passing `&rng` to `randomExpense` would be an overlapping access.
        func append(eventId: EventID, entityId: UUID, payload: EventPayload) {
            seq += 1
            events.append(
                EventEnvelope(
                    eventId: eventId,
                    groupId: groupId,
                    entityId: entityId,
                    authorId: authorId,
                    clientTimestamp: Timestamp(epochMilliseconds: 1_784_000_000_000 + seq * 60_000),
                    serverSeq: seq,
                    payload: payload
                )
            )
        }

        append(
            eventId: EventID(rawValue: rng.nextUUID()),
            entityId: groupId.rawValue,
            payload: .groupCreated(GroupCreatedPayload(name: "Group \(seed)", currency: currency))
        )

        var memberIds: [MemberID] = []
        for index in 0..<rng.nextInt(in: 2...6) {
            let memberId = MemberID(rawValue: rng.nextUUID())
            memberIds.append(memberId)
            append(
                eventId: EventID(rawValue: rng.nextUUID()),
                entityId: memberId.rawValue,
                payload: .memberAdded(MemberAddedPayload(displayName: "Member \(index)"))
            )
        }

        var liveExpenses: [ExpenseID] = []
        var deletedExpenses: [ExpenseID] = []

        for _ in 0..<rng.nextInt(in: 1...maxActions) {
            let eventId = EventID(rawValue: rng.nextUUID())

            switch rng.nextInt(in: 1...100) {

            case 1...40:
                let expenseId = ExpenseID(rawValue: rng.nextUUID())
                let rolled = eventCurrency(&rng)
                let payload = try randomExpense(&rng, members: memberIds, currency: rolled)
                append(eventId: eventId, entityId: expenseId.rawValue, payload: .expenseCreated(payload))
                liveExpenses.append(expenseId)

            case 41...53:
                guard let expenseId = rng.pickIfAny(liveExpenses) else { continue }
                let payload = try randomExpense(&rng, members: memberIds, currency: eventCurrency(&rng))
                append(eventId: eventId, entityId: expenseId.rawValue, payload: .expenseUpdated(payload))

            case 54...63:
                guard let expenseId = rng.pickIfAny(liveExpenses) else { continue }
                append(eventId: eventId, entityId: expenseId.rawValue, payload: .expenseDeleted(EmptyPayload()))
                liveExpenses.removeAll { $0 == expenseId }
                deletedExpenses.append(expenseId)

            case 64...70:
                guard let expenseId = rng.pickIfAny(deletedExpenses) else { continue }
                append(eventId: eventId, entityId: expenseId.rawValue, payload: .expenseRestored(EmptyPayload()))
                deletedExpenses.removeAll { $0 == expenseId }
                liveExpenses.append(expenseId)

            case 71...85:
                guard memberIds.count >= 2 else { continue }
                let pair = rng.pickPair(memberIds)
                let payload = try PaymentRecordedPayload(
                    fromMemberId: pair.0,
                    toMemberId: pair.1,
                    currency: eventCurrency(&rng),
                    amountMinor: rng.nextInt64(in: 1...250_000),
                    date: randomDate(&rng),
                    method: rng.pick([PaymentMethod.cash, .swish, .mobilePay])
                )
                append(eventId: eventId, entityId: rng.nextUUID(), payload: .paymentRecorded(payload))

            case 86...90:
                let memberId = MemberID(rawValue: rng.nextUUID())
                memberIds.append(memberId)
                append(
                    eventId: eventId,
                    entityId: memberId.rawValue,
                    payload: .memberAdded(MemberAddedPayload(displayName: "Late joiner"))
                )

            case 91...93:
                // Removing a member must not disturb the books: they keep their balance.
                guard memberIds.count > 2 else { continue }
                let memberId = rng.pick(memberIds)
                append(eventId: eventId, entityId: memberId.rawValue, payload: .memberRemoved(EmptyPayload()))

            case 94...95:
                // Someone accepts an invite and a placeholder becomes an account (§5). Attaching
                // an identity to a member must not move a single öre — that indirection is the
                // whole reason expenses reference members and never users.
                let memberId = rng.pick(memberIds)
                append(
                    eventId: eventId,
                    entityId: memberId.rawValue,
                    payload: .memberUpdated(
                        MemberUpdatedPayload(
                            displayName: rng.nextInt(in: 1...2) == 1 ? "Renamed" : nil,
                            linkedUserId: UserID(rawValue: rng.nextUUID())
                        )
                    )
                )

            case 96...97:
                // An event from a build that does not exist yet. Must be skipped, not fatal.
                append(
                    eventId: eventId,
                    entityId: rng.nextUUID(),
                    payload: .unknown(
                        type: "FutureEvent\(rng.nextInt(in: 1...3))",
                        raw: .object(["v": .int(rng.nextInt64(in: 0...9999))])
                    )
                )

            default:
                // Re-deliver an earlier event verbatim, as a duplicated sync page would.
                guard let earlier = rng.pickIfAny(events) else { continue }
                seq += 1
                events.append(earlier)
            }
        }

        return GeneratedHistory(
            seed: seed,
            groupId: groupId,
            currency: currency,
            otherCurrencies: otherCurrencies,
            memberIds: memberIds,
            events: events,
            nextServerSeq: seq + 1
        )
    }

    /// A valid expense in a randomly chosen split mode.
    ///
    /// Note the reuse of `Allocator` to build *inputs*: exact amounts and percentage basis points
    /// are themselves produced by allocation, which is the only cheap way to generate values that
    /// are guaranteed to add up to the total (or to 10 000) for any random weighting.
    private static func randomExpense(
        _ rng: inout SeededRandom,
        members: [MemberID],
        currency: CurrencyCode
    ) throws -> ExpensePayload {
        let amount = rng.nextInt64(in: 1...5_000_000)
        let participants = rng.pickSome(members)
        let total = Money(amountMinor: amount, currency: currency)

        let splitInput: SplitInput
        switch rng.nextInt(in: 1...4) {
        case 1:
            splitInput = .equal(among: participants)
        case 2:
            let weights = participants.map { WeightLine(memberId: $0, weight: rng.nextInt64(in: 1...8)) }
            let resolved = try Allocator.allocate(totalMinor: amount, weights: weights)
            splitInput = .exact(resolved)
        case 3:
            let weights = participants.map { WeightLine(memberId: $0, weight: rng.nextInt64(in: 1...8)) }
            let points = try Allocator.allocate(
                totalMinor: SplitInput.percentageTotalBasisPoints,
                weights: weights
            )
            splitInput = .percentage(
                points.map { WeightLine(memberId: $0.memberId, weight: $0.amountMinor) }
            )
        default:
            splitInput = .shares(
                participants.map { WeightLine(memberId: $0, weight: rng.nextInt64(in: 1...8)) }
            )
        }

        // One payer, or two splitting it — both must come out strictly positive.
        let payers: [MoneyLine]
        if amount >= 2, members.count >= 2, rng.chance(30) {
            let pair = rng.pickPair(members)
            payers = try Allocator.allocate(
                totalMinor: amount,
                weights: [
                    WeightLine(memberId: pair.0, weight: 1),
                    WeightLine(memberId: pair.1, weight: 1)
                ]
            )
        } else {
            payers = [MoneyLine(memberId: rng.pick(members), amountMinor: amount)]
        }

        return try ExpensePayload.make(
            description: "Utgift",
            categoryId: rng.pick(["groceries", "restaurang", "taxi", "ovrigt"]),
            date: randomDate(&rng),
            total: total,
            payers: payers,
            splitInput: splitInput
        )
    }

    private static func randomDate(_ rng: inout SeededRandom) -> CalendarDate {
        CalendarDate(
            year: 2026,
            month: rng.nextInt(in: 1...12),
            day: rng.nextInt(in: 1...28)
        ) ?? Fixtures.date
    }
}

extension SeededRandom {
    public mutating func pickIfAny<T>(_ options: [T]) -> T? {
        options.isEmpty ? nil : pick(options)
    }

    /// Two distinct elements. Used for payments, where paying yourself is not representable.
    public mutating func pickPair<T: Equatable>(_ options: [T]) -> (T, T) {
        precondition(options.count >= 2)
        let firstIndex = nextInt(in: 0...(options.count - 1))
        var secondIndex = nextInt(in: 0...(options.count - 2))
        if secondIndex >= firstIndex { secondIndex += 1 }
        return (options[firstIndex], options[secondIndex])
    }
}
