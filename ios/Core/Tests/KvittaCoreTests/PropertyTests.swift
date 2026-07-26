import Foundation
import Testing
import KvittaCoreTestSupport
@testable import KvittaCore

/// The four properties from CLAUDE.md's testing policy, each over 1 000 randomly generated
/// histories.
///
/// These are run as a loop inside one `@Test` rather than as 1 000 parameterised cases: the
/// signal wanted here is "does this property hold", not a thousand lines of test output. Every
/// failure reports the seed that produced it, and `EventSequenceGenerator.make(seed:)` is a pure
/// function of that seed, so any failure can be reproduced exactly by pinning `iterations` to
/// the one seed and re-running.
@Suite("Properties")
struct PropertyTests {
    private let iterations: UInt64 = 1_000

    // MARK: - P1

    @Test("P1: balances in a group sum to exactly zero after any valid event sequence")
    func balancesAlwaysSumToZero() throws {
        for seed in 0..<iterations {
            let history = try EventSequenceGenerator.make(seed: seed)
            let state = Projector.replay(history.events)
            let group = try #require(state.groups[history.groupId], "seed \(seed)")

            let balances = group.balances()
            #expect(balances.totalMinor == 0, "seed \(seed): balances \(balances.byMember)")

            // Zero-sum is trivially satisfiable by projecting nothing at all, so check the fold
            // actually did some work and that nothing legitimate was quietly discarded.
            #expect(
                state.skipped.allSatisfy { isExpectedSkip($0) },
                "seed \(seed): unexpected skips \(state.skipped.map(\.reason))"
            )
        }
    }

    @Test("P1b: every member's balance equals the running total of its own breakdown")
    func breakdownReconcilesWithBalance() throws {
        for seed in 0..<iterations {
            let history = try EventSequenceGenerator.make(seed: seed)
            let state = Projector.replay(history.events)
            let group = try #require(state.groups[history.groupId], "seed \(seed)")
            let balances = group.balances()

            for memberId in group.members.keys {
                let lines = group.breakdown(for: memberId)
                let expected = balances.amountMinor(for: memberId)
                let actual = lines.last?.runningTotalMinor ?? 0
                #expect(actual == expected, "seed \(seed): member \(memberId)")
            }
        }
    }

    // MARK: - P2

    @Test("P2: the same expense input always produces identical shares")
    func roundingIsDeterministic() throws {
        for seed in 0..<iterations {
            var rng = SeededRandom(seed: seed)
            let memberCount = rng.nextInt(in: 2...8)
            let members = (0..<memberCount).map { _ in MemberID(rawValue: rng.nextUUID()) }
            let total = rng.nextInt64(in: 1...9_999_999)
            let weights = members.map { WeightLine(memberId: $0, weight: rng.nextInt64(in: 1...12)) }

            let first = try Allocator.allocate(totalMinor: total, weights: weights)
            let shuffled = try Allocator.allocate(
                totalMinor: total,
                weights: Array(weights.reversed())
            )
            let again = try Allocator.allocate(totalMinor: total, weights: weights)

            // Same answer regardless of input order, and regardless of how often it is asked.
            #expect(first == shuffled, "seed \(seed)")
            #expect(first == again, "seed \(seed)")
            #expect(
                first.reduce(0) { $0 + $1.amountMinor } == total,
                "seed \(seed): shares do not add up to \(total)"
            )

            // And the same again through the public entry point, in every split mode.
            let equal = try SplitCalculator.resolve(
                totalMinor: total,
                input: .equal(among: members)
            )
            let equalReversed = try SplitCalculator.resolve(
                totalMinor: total,
                input: .equal(among: Array(members.reversed()))
            )
            #expect(equal == equalReversed, "seed \(seed)")
        }
    }

    @Test("P2b: shares survive a JSON round trip byte for byte")
    func sharesSurviveEncoding() throws {
        for seed in 0..<iterations {
            let history = try EventSequenceGenerator.make(seed: seed, maxActions: 12)
            for event in history.events where event.payload.expense != nil {
                let data = try EventCoding.encode(event)
                let decoded = try EventCoding.decode(data)
                let reencoded = try EventCoding.encode(decoded)
                #expect(decoded == event, "seed \(seed): event \(event.eventId)")
                #expect(reencoded == data, "seed \(seed): event \(event.eventId)")
            }
        }
    }

    // MARK: - P3

    @Test("P3: pushing the same event batch twice changes nothing")
    func replayingTheSameBatchTwiceIsANoOp() throws {
        for seed in 0..<iterations {
            let history = try EventSequenceGenerator.make(seed: seed)

            let once = Projector.replay(history.events)
            let twice = Projector.replay(history.events, into: once)
            #expect(once == twice, "seed \(seed)")

            // The same thing the other way round: one pass over a doubled batch, as a sync page
            // that overlaps the previous one would deliver it.
            let doubled = Projector.replay(history.events + history.events)
            #expect(doubled == once, "seed \(seed)")

            // And re-delivered out of order, which pull-after-push genuinely does.
            let reversedTail = Projector.replay(Array(history.events.reversed()), into: once)
            #expect(reversedTail == once, "seed \(seed)")
        }
    }

    // MARK: - P4

    @Test("P4: applying the suggested settle-up transfers zeroes every balance")
    func suggestedTransfersSettleTheGroup() throws {
        for seed in 0..<iterations {
            let history = try EventSequenceGenerator.make(seed: seed)
            var state = Projector.replay(history.events)
            let group = try #require(state.groups[history.groupId], "seed \(seed)")

            let transfers = group.suggestedTransfers()

            // At most n-1 transfers, and never a payment to oneself.
            #expect(transfers.count <= max(0, group.members.count - 1), "seed \(seed)")
            #expect(transfers.allSatisfy { $0.from != $0.to }, "seed \(seed)")
            #expect(transfers.allSatisfy { $0.amountMinor > 0 }, "seed \(seed)")

            var seq = history.nextServerSeq
            for transfer in transfers {
                let payload = try PaymentRecordedPayload(
                    fromMemberId: transfer.from,
                    toMemberId: transfer.to,
                    currency: history.currency,
                    amountMinor: transfer.amountMinor,
                    date: Fixtures.date,
                    method: .swish
                )
                state = Projector.apply(
                    state,
                    EventEnvelope(
                        groupId: history.groupId,
                        entityId: UUID(),
                        authorId: UserID(),
                        clientTimestamp: Fixtures.timestamp,
                        serverSeq: seq,
                        payload: .paymentRecorded(payload)
                    )
                )
                seq += 1
            }

            let settled = try #require(state.groups[history.groupId], "seed \(seed)")
            #expect(settled.balances().isSettled, "seed \(seed): \(settled.balances().byMember)")
            #expect(settled.suggestedTransfers().isEmpty, "seed \(seed)")
        }
    }

    // MARK: - Helpers

    /// The generator deliberately emits events the projector is supposed to refuse: unknown types
    /// from a newer build, and re-delivered duplicates. Anything else being skipped means the
    /// projector is dropping legitimate data, which would make P1 pass for the wrong reason.
    private func isExpectedSkip(_ skipped: SkippedEvent) -> Bool {
        switch skipped.reason {
        case .unknownEventType:
            return true
        default:
            return false
        }
    }
}
