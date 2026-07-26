import SwiftUI
import KvittaCore
import KvittaStorage

/// Utgiftsdetalj: the shares, the payer, when it was created and edited, and the two write
/// actions — edit (a full-payload `ExpenseUpdated`) and soft delete (`ExpenseDeleted`).
///
/// Presented by id and read live from the projection, so a save from the edit sheet on top of
/// this one updates these numbers the moment it lands.
struct ExpenseDetailSheet: View {
    let ledger: LedgerStore
    let userId: UserID
    let groupId: GroupID
    let expenseId: ExpenseID

    @Environment(\.dismiss) private var dismiss
    @State private var editModel: NewExpenseModel?
    @State private var confirmingDelete = false
    @State private var failure: String?

    private var group: GroupState? { ledger.state[groupId] }
    private var expense: Expense? { group?.expenses[expenseId] }

    var body: some View {
        if let group, let expense {
            content(group: group, expense: expense)
        } else {
            ContentUnavailableView("Utgiften finns inte längre", systemImage: "questionmark.circle")
                .background(AmbientBackground())
        }
    }

    private func content(group: GroupState, expense: Expense) -> some View {
        let meId = group.me(for: userId)?.id
        return ScrollView {
            VStack(spacing: 14) {
                ExpenseHeader(expense: expense)
                SharesCard(group: group, meId: meId, expense: expense)
                HistoryCard(group: group, expense: expense)

                if let failure {
                    Text(failure).font(.footnote).foregroundStyle(Theme.clay)
                }

                ActionButtons(
                    onEdit: {
                        editModel = NewExpenseModel(
                            ledger: ledger, userId: userId, groupId: groupId, editing: expense
                        )
                    },
                    onDelete: { confirmingDelete = true }
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 26)
        }
        .background(AmbientBackground())
        .sheet(item: $editModel) { model in
            NewExpenseSheet(model: model)
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Ta bort utgiften?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Ta bort", role: .destructive, action: delete)
        } message: {
            Text("Den går att återställa under Visa borttagna.")
        }
    }

    private func delete() {
        do {
            // Soft delete: the event stays in the log, "Visa borttagna" and restore both work.
            try ledger.record(.expenseDeleted(EmptyPayload()), entityId: expenseId.rawValue, in: groupId)
            dismiss()
        } catch {
            failure = String(describing: error)
        }
    }
}

// MARK: - Sections

private struct ExpenseHeader: View {
    let expense: Expense

    var body: some View {
        VStack(spacing: 8) {
            Text(Categories.emoji(for: expense.categoryId))
                .font(.system(size: 30))
                .frame(width: 64, height: 64)
                .background(Color(hex: 0xF5EBDD), in: .circle)
            Text(expense.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            NeutralAmountText(amountMinor: expense.amountMinor, currency: expense.currency, size: 34)
            Text(expense.date.displayString)
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SharesCard: View {
    let group: GroupState
    let meId: MemberID?
    let expense: Expense

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(expense.payload.payers.enumerated()), id: \.element.memberId) { _, line in
                LabeledContent {
                    NeutralAmountText(amountMinor: line.amountMinor, currency: expense.currency, size: 15)
                } label: {
                    Text("\(name(line.memberId)) betalade").foregroundStyle(Theme.ink)
                }
                .padding(.vertical, 8)
            }
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ForEach(Array(expense.payload.shares.enumerated()), id: \.element.memberId) { index, line in
                if index > 0 {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
                LabeledContent {
                    NeutralAmountText(amountMinor: line.amountMinor, currency: expense.currency, size: 15)
                } label: {
                    Text(name(line.memberId)).foregroundStyle(Theme.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .font(.subheadline)
        .cardSurface(padding: 14)
    }

    private func name(_ memberId: MemberID) -> String {
        if memberId == meId { return String(localized: "Du") }
        return group.members[memberId]?.displayName ?? "?"
    }
}

/// Created / last edited, straight off the projected entity. The full event-by-event history
/// belongs to a later round once the store exposes per-entity event queries.
private struct HistoryCard: View {
    let group: GroupState
    let expense: Expense

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Skapad \(expense.createdAt.date.formatted(date: .abbreviated, time: .shortened))\(author(expense.createdBy))")
            if expense.wasEdited {
                Text("Redigerad \(expense.revision) gånger · senast \(expense.lastModifiedAt.date.formatted(date: .abbreviated, time: .shortened))\(author(expense.lastModifiedBy))")
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 14)
    }

    /// " av Jonas" when the author maps to a member of this group, empty otherwise. Only linked
    /// members are mappable — placeholder members never author events.
    private func author(_ userId: UserID) -> String {
        guard let member = group.members.values.first(where: { $0.linkedUserId == userId }) else {
            return ""
        }
        return " av \(member.displayName)"
    }
}

private struct ActionButtons: View {
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onEdit) {
                Text("Redigera")
                    .font(.headline)
                    .foregroundStyle(Color(hex: 0xF6F1E7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .glassEffect(.regular.tint(Theme.espresso).interactive(), in: .rect(cornerRadius: 24))

            Button(role: .destructive, action: onDelete) {
                Text("Ta bort")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .foregroundStyle(Theme.clay)
        }
        .padding(.top, 6)
    }
}

extension CalendarDate {
    /// "26 juli 2026", locale-aware. Display only; the wire format stays ISO 8601.
    var displayString: String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = Calendar.current.date(from: components) else { return iso8601 }
        return date.formatted(date: .long, time: .omitted)
    }
}
