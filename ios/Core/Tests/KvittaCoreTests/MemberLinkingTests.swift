import Foundation
import Testing
import KvittaCoreTestSupport
@testable import KvittaCore

/// Attaching an account to a member who already exists (design doc §5).
///
/// The property that matters is the boring one: linking moves no money. Expenses reference
/// members, never users, which is exactly why someone can join a group months after the spending
/// happened and inherit a history that already balances.
@Suite("Member linking")
struct MemberLinkingTests {
    private let members = (1...3).map { Fixtures.member($0) }
    private let joiner = UserID(uuidString: "00000000-0000-0000-00dd-000000000001")!

    /// Three members and one 437.00 kr expense split equally. Member 2 is a placeholder.
    private func groupWithHistory(_ factory: inout EventFactory) throws -> [EventEnvelope] {
        var events: [EventEnvelope] = [factory.groupCreated()]

        for (index, memberId) in members.enumerated() {
            events.append(factory.memberAdded(memberId, name: "Member \(index + 1)"))
        }

        events.append(factory.expenseCreated(Fixtures.expense(1), try ExpensePayload.make(
            description: "Systembolaget",
            categoryId: "alkohol",
            date: Fixtures.date,
            total: Money(amountMinor: 43_700, currency: .sek),
            paidBy: members[0],
            splitEquallyAmong: members
        )))

        return events
    }

    @Test("Linking an account to a placeholder leaves every balance untouched")
    func linkingMovesNoMoney() throws {
        var factory = EventFactory()
        let history = try groupWithHistory(&factory)
        let before = try #require(Projector.replay(history).groups[Fixtures.groupId]).balances()

        let linked = history + [factory.memberUpdated(members[1], linkedUserId: joiner)]
        let after = try #require(Projector.replay(linked).groups[Fixtures.groupId]).balances()

        #expect(after.byMember == before.byMember)
        #expect(after.totalMinor == 0)
    }

    @Test("The placeholder becomes the joiner's own member")
    func linkingAttachesTheUser() throws {
        var factory = EventFactory()
        let history = try groupWithHistory(&factory)
        let events = history + [factory.memberUpdated(members[1], linkedUserId: joiner)]

        let group = try #require(Projector.replay(events).groups[Fixtures.groupId])

        #expect(group.members[members[1]]?.linkedUserId == joiner)

        // And the whole point: their share of a bill from before they joined is already theirs.
        // This is the lookup every screen does to find "you" in a group.
        let mine = group.members.values.first { $0.linkedUserId == joiner }
        #expect(mine?.id == members[1])
        #expect(group.balances().money(for: members[1]).amountMinor == -14_567)
    }

    @Test("A rename leaves the link alone, and a link leaves the name alone")
    func absentFieldsMeanUnchanged() throws {
        var factory = EventFactory()
        let history = try groupWithHistory(&factory)

        let events = history + [
            factory.memberUpdated(members[1], name: "Jonas"),
            factory.memberUpdated(members[1], linkedUserId: joiner)
        ]

        let group = try #require(Projector.replay(events).groups[Fixtures.groupId])

        #expect(group.members[members[1]]?.displayName == "Jonas")
        #expect(group.members[members[1]]?.linkedUserId == joiner)
    }

    @Test("Updating a member nobody has heard of is skipped, not fatal")
    func unknownMemberIsSkipped() throws {
        var factory = EventFactory()
        let history = try groupWithHistory(&factory)
        let stranger = Fixtures.member(99)

        let state = Projector.replay(history + [factory.memberUpdated(stranger, linkedUserId: joiner)])
        let group = try #require(state.groups[Fixtures.groupId])

        #expect(group.members[stranger] == nil)
        #expect(group.balances().totalMinor == 0)
    }

    @Test("A MemberUpdated survives an encode/decode round trip")
    func roundTrips() throws {
        var factory = EventFactory()
        _ = try groupWithHistory(&factory)
        let event = factory.memberUpdated(members[1], name: "Jonas", linkedUserId: joiner)

        let decoded = try EventCoding.decode(try EventCoding.encode(event))

        #expect(decoded == event)
        #expect(decoded.type == EventType.memberUpdated)
    }
}
