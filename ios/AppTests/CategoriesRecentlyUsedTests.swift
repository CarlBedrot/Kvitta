import Foundation
import Testing
import KvittaCore
@testable import Kvitta

/// The Steven 9 chip row (#153) puts a group's most recently used categories first, so this is
/// pure data shaping over `GroupState.visibleExpenses` — no ledger, no view, just `GroupState`
/// built by hand with the expenses already in place.
struct CategoriesRecentlyUsedTests {
    private let payer = MemberID()

    private func expense(_ categoryId: String, day: Int) -> Expense {
        let payload = try! ExpensePayload.make(
            description: "test \(categoryId)",
            categoryId: categoryId,
            date: CalendarDate(year: 2026, month: 10, day: day) ?? .epoch,
            total: Money(amountMinor: 1_000, currency: .sek),
            paidBy: payer,
            splitEquallyAmong: [payer]
        )
        return Expense(id: ExpenseID(), payload: payload, createdBy: UserID(), createdAt: Timestamp(Date()),
                        lastModifiedBy: UserID(), lastModifiedAt: Timestamp(Date()))
    }

    private func group(_ categoriesNewestFirst: [(String, Int)]) -> GroupState {
        var expenses: [ExpenseID: Expense] = [:]
        for (categoryId, day) in categoriesNewestFirst {
            let item = expense(categoryId, day: day)
            expenses[item.id] = item
        }
        return GroupState(id: GroupID(), name: "Test", currency: .sek, expenses: expenses)
    }

    @Test func mostRecentCategoryComesFirstAndIsNeverRepeated() {
        // Newest first: taxi (day 20), groceries (day 19), taxi again (day 18, older, ignored).
        let state = group([("taxi", 20), ("groceries", 19), ("taxi", 18)])
        let result = Categories.recentlyUsed(in: state, limit: 5)

        #expect(result.map(\.id).prefix(2) == ["taxi", "groceries"])
        #expect(result.filter { $0.id == "taxi" }.count == 1)
    }

    @Test func noExpensesFallsBackToTheFullSetInItsDefinedOrder() {
        let result = Categories.recentlyUsed(in: nil, limit: 5)
        #expect(result.map(\.id) == Categories.all.prefix(5).map(\.id))
    }

    @Test func limitIsRespectedAndTheRestFillsFromTheFullSet() {
        let state = group([("taxi", 20)])
        let result = Categories.recentlyUsed(in: state, limit: 3)

        #expect(result.count == 3)
        #expect(result.first?.id == "taxi")
        // The remaining slots come from the full list, taxi not repeated.
        #expect(Set(result.map(\.id)).count == 3)
    }
}
