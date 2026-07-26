import Testing
import KvittaCoreTestSupport
@testable import KvittaCore

@Suite("ExpensePayload money invariant")
struct ExpensePayloadTests {
    private let members = (1...3).map { Fixtures.member($0) }

    private func payload(
        amountMinor: Int64,
        payers: [MoneyLine],
        shares: [MoneyLine]
    ) throws -> ExpensePayload {
        try ExpensePayload(
            description: "Systembolaget",
            categoryId: "alkohol",
            date: Fixtures.date,
            currency: Fixtures.currency,
            amountMinor: amountMinor,
            payers: payers,
            shares: shares,
            splitMethod: .exact
        )
    }

    @Test("A balanced expense is accepted and its lines come out sorted")
    func balancedExpenseIsAccepted() throws {
        let expense = try payload(
            amountMinor: 300,
            payers: [MoneyLine(memberId: members[1], amountMinor: 300)],
            shares: [
                MoneyLine(memberId: members[2], amountMinor: 100),
                MoneyLine(memberId: members[0], amountMinor: 100),
                MoneyLine(memberId: members[1], amountMinor: 100)
            ]
        )
        #expect(expense.shares.map(\.memberId) == members)
        #expect(expense.total == Fixtures.money(300))
    }

    @Test("Shares that do not add up to the amount are rejected")
    func sharesMustMatchAmount() {
        #expect(throws: CoreError.invariantViolated(amountMinor: 300, payersTotal: 300, sharesTotal: 299)) {
            try payload(
                amountMinor: 300,
                payers: [MoneyLine(memberId: members[0], amountMinor: 300)],
                shares: [
                    MoneyLine(memberId: members[0], amountMinor: 150),
                    MoneyLine(memberId: members[1], amountMinor: 149)
                ]
            )
        }
    }

    @Test("Payers that do not add up to the amount are rejected")
    func payersMustMatchAmount() {
        #expect(throws: CoreError.invariantViolated(amountMinor: 300, payersTotal: 250, sharesTotal: 300)) {
            try payload(
                amountMinor: 300,
                payers: [MoneyLine(memberId: members[0], amountMinor: 250)],
                shares: [MoneyLine(memberId: members[1], amountMinor: 300)]
            )
        }
    }

    @Test("An expense of zero or less is not an expense")
    func amountMustBePositive() {
        #expect(throws: CoreError.nonPositiveAmount(field: "amountMinor", value: 0)) {
            try payload(
                amountMinor: 0,
                payers: [MoneyLine(memberId: members[0], amountMinor: 0)],
                shares: [MoneyLine(memberId: members[0], amountMinor: 0)]
            )
        }
    }

    @Test("A payer who paid nothing is not a payer")
    func payerAmountsMustBePositive() {
        #expect(throws: CoreError.self) {
            try payload(
                amountMinor: 300,
                payers: [
                    MoneyLine(memberId: members[0], amountMinor: 300),
                    MoneyLine(memberId: members[1], amountMinor: 0)
                ],
                shares: [MoneyLine(memberId: members[0], amountMinor: 300)]
            )
        }
    }

    @Test("A share of zero is fine — an exact split may genuinely leave someone out")
    func zeroShareIsAllowed() throws {
        let expense = try payload(
            amountMinor: 300,
            payers: [MoneyLine(memberId: members[0], amountMinor: 300)],
            shares: [
                MoneyLine(memberId: members[0], amountMinor: 300),
                MoneyLine(memberId: members[1], amountMinor: 0)
            ]
        )
        #expect(expense.share(of: members[1]) == 0)
    }

    @Test("A negative share is not")
    func negativeShareIsRejected() {
        #expect(throws: CoreError.negativeShare(memberId: Fixtures.member(2), value: -100)) {
            try payload(
                amountMinor: 300,
                payers: [MoneyLine(memberId: members[0], amountMinor: 300)],
                shares: [
                    MoneyLine(memberId: members[0], amountMinor: 400),
                    MoneyLine(memberId: members[1], amountMinor: -100)
                ]
            )
        }
    }

    @Test("The same member cannot appear twice in one list")
    func duplicateMembersRejected() {
        #expect(throws: CoreError.duplicateMember(memberId: Fixtures.member(1), field: "shares")) {
            try payload(
                amountMinor: 300,
                payers: [MoneyLine(memberId: members[0], amountMinor: 300)],
                shares: [
                    MoneyLine(memberId: members[0], amountMinor: 150),
                    MoneyLine(memberId: members[0], amountMinor: 150)
                ]
            )
        }
    }

    @Test("Empty payers or empty shares are rejected")
    func emptyListsRejected() {
        #expect(throws: CoreError.emptyLineItems(field: "payers")) {
            try payload(
                amountMinor: 300,
                payers: [],
                shares: [MoneyLine(memberId: members[0], amountMinor: 300)]
            )
        }
        #expect(throws: CoreError.emptyLineItems(field: "shares")) {
            try payload(
                amountMinor: 300,
                payers: [MoneyLine(memberId: members[0], amountMinor: 300)],
                shares: []
            )
        }
    }

    @Test("The one-payer equal-split convenience produces a valid expense")
    func equalSplitConvenience() throws {
        let expense = try ExpensePayload.make(
            description: "Middag",
            categoryId: "restaurang",
            date: Fixtures.date,
            total: Fixtures.money(43_700),
            paidBy: members[0],
            splitEquallyAmong: members
        )

        #expect(expense.paid(by: members[0]) == 43_700)
        #expect(expense.shares.map(\.amountMinor) == [14_567, 14_567, 14_566])
        #expect(expense.splitMethod == .equal)
        #expect(expense.involvedMembers == Set(members))
    }
}
