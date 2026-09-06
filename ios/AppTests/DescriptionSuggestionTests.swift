import Foundation
import Testing
import KvittaCore
import KvittaStorage
@testable import Kvitta

/// The chips on the add sheet are the app's memory of what this group buys. A household should
/// see "Hyra · Internet" and a trip "Middag · Taxi" — and the same word typed twice, or typed in a
/// different case, must not become two chips.
@MainActor
struct DescriptionSuggestionTests {

    private func group(with descriptions: [(String, String)]) throws -> GroupState {
        let ledger = LedgerStore(store: try EventStore.inMemory(), authorId: UserID())
        let groupId = GroupID()
        try ledger.record(
            .groupCreated(GroupCreatedPayload(name: "Hemma", currency: .sek)),
            entityId: groupId.rawValue, in: groupId
        )
        let member = MemberID()
        try ledger.record(
            .memberAdded(MemberAddedPayload(displayName: "Kim")),
            entityId: member.rawValue, in: groupId
        )
        for (index, (description, categoryId)) in descriptions.enumerated() {
            try ledger.record(
                .expenseCreated(try ExpensePayload.make(
                    description: description,
                    categoryId: categoryId,
                    date: CalendarDate(year: 2026, month: 9, day: 1 + index)!,
                    total: Money(amountMinor: 10_000, currency: .sek),
                    paidBy: member,
                    splitEquallyAmong: [member]
                )),
                entityId: ExpenseID().rawValue, in: groupId
            )
        }
        return ledger.state[groupId]!
    }

    @Test("A fresh group gets exactly the starters")
    func freshGroupIsStarters() throws {
        let suggestions = DescriptionSuggestion.suggestions(for: try group(with: []))
        #expect(suggestions.map(\.text) == DescriptionSuggestion.starters.map(\.text))
    }

    @Test("The group's own recent descriptions come first, newest first, without repeats")
    func recentFirstThenStarters() throws {
        let group = try group(with: [("Hyra", "boende"), ("Hyra", "boende"), ("Internet", "övrigt")])
        let suggestions = DescriptionSuggestion.suggestions(for: group)

        #expect(Array(suggestions.map(\.text).prefix(2)) == ["Internet", "Hyra"])
        #expect(suggestions.filter { $0.text == "Hyra" }.count == 1)
        // The rest are starters, in their own order, and nothing beyond the cap.
        let rest = suggestions.dropFirst(2).map(\.text)
        #expect(rest == Array(DescriptionSuggestion.starters.map(\.text).prefix(rest.count)))
        #expect(suggestions.count <= 8)
    }

    @Test("Case and whitespace do not make a second chip, and the recent one wins")
    func caseInsensitiveDedupe() throws {
        let group = try group(with: [("  ica ", "groceries"), ("Middag", "restaurang")])
        let suggestions = DescriptionSuggestion.suggestions(for: group)

        #expect(suggestions.filter { $0.text.lowercased() == "ica" }.count == 1)
        #expect(suggestions.filter { $0.text == "Middag" }.count == 1)
        #expect(suggestions.first?.text == "Middag")
        #expect(suggestions[1].text == "ica")
    }
}
