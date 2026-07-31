import Foundation
import Testing
import KvittaCoreTestSupport
@testable import KvittaCore

/// Guards the assumption the storage design rests on.
///
/// Projections are held in memory and rebuilt from the log at launch rather than cached in the
/// database. That is only defensible while a full replay is imperceptible — `ui-design.md` is
/// explicit that there is never a loading state on launch, and the design doc claims a
/// 5 000-event group replays "well under a second". If that stops being true, the answer is
/// projection tables in GRDB, and this is where you find out.
///
/// Run it in release (`swift test -c release`). A debug build is five times slower and says
/// nothing useful about what a shipped app does.
@Suite("Replay performance")
struct ReplayPerformanceTests {

    /// Deliberately loose. The measured figure is a small fraction of this; the bound exists to
    /// catch a collapse — an accidental quadratic — not to police variance on a busy machine.
    ///
    /// Only enforced in release. An unoptimised build runs this same log about twenty times
    /// slower, which lands close enough to the bound to fail whenever the machine is busy — and a
    /// test that fails for reasons unrelated to the code is worse than no test at all. Debug runs
    /// still print the numbers, so `swift test` remains useful for spotting a change in shape.
    private let budgetSeconds = 1.0

    private var enforcesBudget: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    @Test("A heavy group replays fast enough that launch needs no loading state")
    func heavyGroupReplaysQuickly() throws {
        let events = HeavyGroup.log(eventCount: 5_000)

        // Prefixes of a log are themselves valid logs, so this shows the shape of the curve:
        // linear cost per event keeps the µs/event column flat.
        for count in [1_000, 2_500, events.count] {
            let prefix = Array(events.prefix(count))
            let began = DispatchTime.now().uptimeNanoseconds
            _ = Projector.replay(prefix)
            let took = Double(DispatchTime.now().uptimeNanoseconds - began) / 1_000_000_000
            print("[replay] \(count) events: \(String(format: "%.1f", took * 1000)) ms "
                + "(\(String(format: "%.2f", took * 1_000_000 / Double(count))) µs/event)")
        }

        let start = DispatchTime.now().uptimeNanoseconds
        let state = Projector.replay(events)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000

        // Sanity: the fold did real work rather than skipping everything.
        let group = try #require(state.groups[HeavyGroup.groupId])
        #expect(group.expenses.count > 1_000)
        #expect(group.primaryBalances().totalMinor == 0)

        if enforcesBudget {
            #expect(elapsed < budgetSeconds, "replay of \(events.count) events took \(elapsed)s")
        }
    }
}

/// A log shaped like a real friend group rather than like the property-test generator.
///
/// This distinction turned out to matter enormously. `EventSequenceGenerator` grows its member
/// list as it goes and splits each expense across most of it, so a long generated history ends up
/// with hundreds of members and ~117 share lines per expense — which is genuinely quadratic work,
/// but in the data, not the code. Six people splitting five thousand expenses is the case the app
/// actually has to be fast for.
enum HeavyGroup {
    static let groupId = GroupID(uuidString: "00000000-0000-0000-00ff-000000000001")!
    static let authorId = UserID(uuidString: "00000000-0000-0000-00ff-000000000002")!

    static func log(eventCount: Int) -> [EventEnvelope] {
        var rng = SeededRandom(seed: 20_260_726)
        let members = (1...6).map { Fixtures.member($0) }

        var events: [EventEnvelope] = []
        events.reserveCapacity(eventCount + members.count + 1)
        var seq: Int64 = 0

        func append(entityId: UUID, _ payload: EventPayload) {
            seq += 1
            events.append(
                EventEnvelope(
                    eventId: EventID(rawValue: rng.nextUUID()),
                    groupId: groupId,
                    entityId: entityId,
                    authorId: authorId,
                    clientTimestamp: Timestamp(epochMilliseconds: 1_784_000_000_000 + seq * 60_000),
                    serverSeq: seq,
                    payload: payload
                )
            )
        }

        append(entityId: groupId.rawValue, .groupCreated(
            GroupCreatedPayload(name: "Fjällresan", currency: .sek)
        ))
        for (index, memberId) in members.enumerated() {
            append(entityId: memberId.rawValue, .memberAdded(
                MemberAddedPayload(displayName: "Member \(index + 1)")
            ))
        }

        var liveExpenses: [ExpenseID] = []

        func expense() -> ExpensePayload {
            let amount = rng.nextInt64(in: 5_000...250_000)
            let participants = rng.pickSome(members, atLeast: 2)
            // swiftlint:disable:next force_try — inputs are constructed valid by definition here
            return try! ExpensePayload.make(
                description: "Utgift",
                categoryId: "restaurang",
                date: Fixtures.date,
                total: Money(amountMinor: amount, currency: .sek),
                paidBy: rng.pick(members),
                splitEquallyAmong: participants
            )
        }

        while events.count < eventCount {
            switch rng.nextInt(in: 1...100) {
            case 1...70:
                let expenseId = ExpenseID(rawValue: rng.nextUUID())
                append(entityId: expenseId.rawValue, .expenseCreated(expense()))
                liveExpenses.append(expenseId)

            case 71...85:
                guard let expenseId = rng.pickIfAny(liveExpenses) else { continue }
                append(entityId: expenseId.rawValue, .expenseUpdated(expense()))

            case 86...90:
                guard let expenseId = rng.pickIfAny(liveExpenses) else { continue }
                append(entityId: expenseId.rawValue, .expenseDeleted(EmptyPayload()))
                liveExpenses.removeAll { $0 == expenseId }

            default:
                let pair = rng.pickPair(members)
                guard let payment = try? PaymentRecordedPayload(
                    fromMemberId: pair.0,
                    toMemberId: pair.1,
                    currency: .sek,
                    amountMinor: rng.nextInt64(in: 1_000...50_000),
                    date: Fixtures.date,
                    method: .swish
                ) else { continue }
                append(entityId: rng.nextUUID(), .paymentRecorded(payment))
            }
        }

        return events
    }
}
