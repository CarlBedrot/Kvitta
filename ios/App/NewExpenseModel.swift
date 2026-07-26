import Foundation
import KvittaCore
import KvittaStorage

/// All the state behind the Ny utgift sheet, and the one place it becomes an event.
///
/// It never builds shares by hand: `resolvedPayload()` hands the amount, payer, and the editor's
/// `SplitInput` to `ExpensePayload.make`, which resolves the split through `SplitCalculator` and
/// enforces `sum(payers) == sum(shares) == amountMinor` before the value can exist. `isValid` is
/// just "does that succeed", so Spara can never write a broken expense.
@MainActor
@Observable
final class NewExpenseModel: Identifiable {
    /// Identifies a presentation of the sheet, so `.sheet(item:)` can drive it.
    nonisolated let id = UUID()
    let ledger: LedgerStore
    let userId: UserID

    private(set) var groupId: GroupID
    var amount = AmountInput()
    var descriptionText = ""
    var categoryId = Categories.fallbackId
    var payerId: MemberID?
    var draft: SplitDraft
    var failure: String?

    init(ledger: LedgerStore, userId: UserID, groupId: GroupID) {
        self.ledger = ledger
        self.userId = userId
        self.groupId = groupId
        let group = ledger.state[groupId]
        let memberIds = (group?.activeMembers ?? []).map(\.id)
        self.draft = SplitDraft(members: memberIds)
        self.payerId = group?.me(for: userId)?.id ?? memberIds.first
    }

    // MARK: - Group context (derived from the live projection)

    var group: GroupState? { ledger.state[groupId] }
    var members: [Member] { group?.activeMembers ?? [] }
    var memberIds: [MemberID] { members.map(\.id) }
    var currency: CurrencyCode { group?.currency ?? .sek }
    var amountMinor: Int64 { amount.amountMinor }

    /// Switching the group resets the split and payer to the new membership.
    func selectGroup(_ id: GroupID) {
        groupId = id
        let ids = memberIds
        draft = SplitDraft(members: ids)
        payerId = group?.me(for: userId)?.id ?? ids.first
    }

    // MARK: - Payer display

    var payerMember: Member? { members.first { $0.id == payerId } }
    var isPayerMe: Bool { payerId != nil && payerId == group?.me(for: userId)?.id }

    /// A member's name for display, showing the linked local member as "Du" (localized).
    func name(for member: Member) -> String {
        member.id == group?.me(for: userId)?.id ? String(localized: "Du") : member.displayName
    }

    // MARK: - Building the expense

    func resolvedPayload() throws -> ExpensePayload {
        guard let payerId else { throw NewExpenseError.noPayer }
        let total = Money(amountMinor: amountMinor, currency: currency)
        return try ExpensePayload.make(
            description: descriptionText.trimmingCharacters(in: .whitespaces),
            categoryId: categoryId,
            date: CalendarDate(Date()),
            total: total,
            payers: [MoneyLine(memberId: payerId, amountMinor: amountMinor)],
            splitInput: draft.splitInput(members: memberIds)
        )
    }

    var isValid: Bool {
        amountMinor > 0 && (try? resolvedPayload()) != nil
    }

    /// Writes the expense. Local and immediate — no network, no spinner. Returns whether it stuck
    /// so the sheet only dismisses on success and a failure stays on screen (CLAUDE.md).
    @discardableResult
    func save() -> Bool {
        do {
            let payload = try resolvedPayload()
            try ledger.record(.expenseCreated(payload), entityId: ExpenseID().rawValue, in: groupId)
            return true
        } catch {
            failure = String(describing: error)
            return false
        }
    }
}

enum NewExpenseError: Error {
    case noPayer
}
