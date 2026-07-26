import Testing
import KvittaCoreTestSupport
@testable import KvittaCore

@Suite("DebtSimplifier")
struct DebtSimplifierTests {
    private let members = (1...4).map { Fixtures.member($0) }

    @Test("Nobody owes anybody anything")
    func settledGroupNeedsNoTransfers() {
        let balances = Balances(currency: .sek, byMember: [members[0]: 0, members[1]: 0])
        #expect(DebtSimplifier.simplify(balances).isEmpty)
    }

    @Test("One debtor, one creditor, one transfer")
    func simplestCase() {
        let balances = Balances(
            currency: .sek,
            byMember: [members[0]: 15_000, members[1]: -15_000]
        )
        #expect(DebtSimplifier.simplify(balances)
            == [SuggestedTransfer(from: members[1], to: members[0], amountMinor: 15_000)])
    }

    @Test("A chain of debts collapses into at most n-1 transfers")
    func chainCollapses() {
        // Four people, three of whom owe the fourth different amounts.
        let balances = Balances(currency: .sek, byMember: [
            members[0]: 6_000,
            members[1]: -1_000,
            members[2]: -2_000,
            members[3]: -3_000
        ])
        let transfers = DebtSimplifier.simplify(balances)

        #expect(transfers.count <= members.count - 1)
        #expect(transfers.allSatisfy { $0.to == members[0] })
        #expect(transfers.reduce(0) { $0 + $1.amountMinor } == 6_000)
    }

    @Test("Largest debtor is matched against largest creditor")
    func greedyMatchesLargestFirst() {
        let balances = Balances(currency: .sek, byMember: [
            members[0]: 5_000,
            members[1]: 1_000,
            members[2]: -4_000,
            members[3]: -2_000
        ])
        let transfers = DebtSimplifier.simplify(balances)

        #expect(transfers == [
            SuggestedTransfer(from: members[2], to: members[0], amountMinor: 4_000),
            SuggestedTransfer(from: members[3], to: members[0], amountMinor: 1_000),
            SuggestedTransfer(from: members[3], to: members[1], amountMinor: 1_000)
        ])
        #expect(transfers.count <= members.count - 1)
    }

    @Test("Equal amounts break the tie on member id, so two devices agree")
    func tiesBreakOnMemberId() {
        let balances = Balances(currency: .sek, byMember: [
            members[0]: 1_000,
            members[1]: 1_000,
            members[2]: -1_000,
            members[3]: -1_000
        ])
        let transfers = DebtSimplifier.simplify(balances)

        #expect(transfers == [
            SuggestedTransfer(from: members[2], to: members[0], amountMinor: 1_000),
            SuggestedTransfer(from: members[3], to: members[1], amountMinor: 1_000)
        ])
    }

    @Test("Suggestions never point a member at themselves")
    func neverSuggestsSelfPayment() {
        let balances = Balances(currency: .sek, byMember: [
            members[0]: 3_000,
            members[1]: -1_000,
            members[2]: -2_000
        ])
        #expect(DebtSimplifier.simplify(balances).allSatisfy { $0.from != $0.to })
    }

    @Test("Every suggested transfer is for a positive amount")
    func amountsArePositive() {
        let balances = Balances(currency: .sek, byMember: [
            members[0]: 7,
            members[1]: -3,
            members[2]: -4
        ])
        #expect(DebtSimplifier.simplify(balances).allSatisfy { $0.amountMinor > 0 })
    }
}
