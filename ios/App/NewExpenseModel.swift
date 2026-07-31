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
    /// Which event `save()` writes: a fresh expense, or a full-payload correction to an existing
    /// one. Corrections are new `ExpenseUpdated` events on the same entity — never edits to
    /// stored events (CLAUDE.md).
    enum Purpose {
        case create
        case edit(ExpenseID)
    }

    /// Identifies a presentation of the sheet, so `.sheet(item:)` can drive it.
    nonisolated let id = UUID()
    let ledger: LedgerStore
    let userId: UserID
    let purpose: Purpose

    private(set) var groupId: GroupID
    var amount = AmountInput()
    var descriptionText = ""
    var categoryId = Categories.fallbackId
    /// The expense's own currency (M7). Defaults to the group's primary; a Copenhagen dinner in
    /// a SEK group is entered as DKK and lands in the DKK bucket, no conversion anywhere.
    var currency: CurrencyCode = .sek
    var payerId: MemberID?
    var draft: SplitDraft
    var failure: String?
    /// The day the expense belongs to. Today for a new expense; preserved on edit, because
    /// correcting a typo in the amount does not move the dinner to another day.
    private var date: CalendarDate

    init(ledger: LedgerStore, userId: UserID, groupId: GroupID) {
        self.ledger = ledger
        self.userId = userId
        self.groupId = groupId
        self.purpose = .create
        self.date = CalendarDate(Date())
        let group = ledger.state[groupId]
        let memberIds = (group?.activeMembers ?? []).map(\.id)
        self.draft = SplitDraft(members: memberIds)
        self.payerId = group?.me(for: userId)?.id ?? memberIds.first
        self.currency = group?.currency ?? .sek
    }

    /// Prefills the sheet from an existing expense, reopening the split editor in the mode the
    /// expense was created in (`splitInput` is stored on the payload for exactly this).
    init(ledger: LedgerStore, userId: UserID, groupId: GroupID, editing expense: Expense) {
        self.ledger = ledger
        self.userId = userId
        self.groupId = groupId
        self.purpose = .edit(expense.id)
        self.date = expense.date
        self.amount = AmountInput(amountMinor: expense.amountMinor)
        self.descriptionText = expense.title
        self.categoryId = expense.categoryId
        self.payerId = expense.payload.payers.first?.memberId
        // An edit keeps the stored currency: a correction to the amount is not a re-denomination.
        self.currency = expense.currency
        let memberIds = (ledger.state[groupId]?.activeMembers ?? []).map(\.id)
        self.draft = SplitDraft(
            splitInput: expense.payload.splitInput,
            resolvedShares: expense.payload.shares,
            members: memberIds
        )
    }

    var isEditing: Bool {
        if case .edit = purpose { return true }
        return false
    }

    // MARK: - Group context (derived from the live projection)

    var group: GroupState? { ledger.state[groupId] }
    var members: [Member] { group?.activeMembers ?? [] }
    var memberIds: [MemberID] { members.map(\.id) }
    var amountMinor: Int64 { amount.amountMinor }

    /// Switching the group resets the split, payer and currency to the new group's.
    func selectGroup(_ id: GroupID) {
        groupId = id
        let ids = memberIds
        draft = SplitDraft(members: ids)
        payerId = group?.me(for: userId)?.id ?? ids.first
        currency = group?.currency ?? .sek
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
            date: date,
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
            switch purpose {
            case .create:
                try ledger.record(.expenseCreated(payload), entityId: ExpenseID().rawValue, in: groupId)
            case .edit(let expenseId):
                // A full replacement on the same entity; the old version stays in the log and
                // becomes the edit history.
                try ledger.record(.expenseUpdated(payload), entityId: expenseId.rawValue, in: groupId)
            }
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
