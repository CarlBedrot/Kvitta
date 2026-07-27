import SwiftUI
import KvittaCore
import KvittaStorage

/// Gruppvy: your balance on the zero line, who owes whom, and the expense list by month.
///
/// Everything here is a read of the projection — `balances()`, `suggestedTransfers()`,
/// `visibleExpenses` — plus one write path: a transfer's "Gör upp" opens `SettleUpSheet`, which
/// records a `PaymentRecorded` through `LedgerStore.record`. Glass on this screen: the system
/// tab bar and the per-transfer "Gör upp" buttons.
struct GroupDetailView: View {
    let ledger: LedgerStore
    let userId: UserID
    let groupId: GroupID
    var payees = PayeeDirectory()

    @State private var settlingTransfer: TransferPresentation?
    @State private var auditingMember: MemberID?
    @State private var viewingExpense: ExpenseID?
    @State private var showingDeleted = false
    @State private var restoreFailure: String?

    /// The live group out of the projection. `nil` only if the group vanished mid-navigation,
    /// which a rebuild from a bad log could theoretically produce — show nothing rather than crash.
    private var group: GroupState? { ledger.state[groupId] }

    var body: some View {
        if let group {
            content(for: group)
        } else {
            ContentUnavailableView("Gruppen finns inte längre", systemImage: "person.2.slash")
                .background(AmbientBackground())
        }
    }

    private func content(for group: GroupState) -> some View {
        let meId = group.me(for: userId)?.id
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // The trust rule (product principles): every balance on screen opens the exact
                // lines behind it. The card audits you; a transfer row audits the counterparty.
                Button {
                    if let meId { auditingMember = meId }
                } label: {
                    GroupBalanceCard(group: group, userId: userId)
                }
                .buttonStyle(.plain)

                TransfersCard(
                    group: group,
                    meId: meId,
                    onSettle: { settlingTransfer = TransferPresentation(transfer: $0) },
                    onAudit: { auditingMember = $0 }
                )
                ExpenseList(group: group, meId: meId) { viewingExpense = $0 }
                DeletedExpensesSection(
                    group: group,
                    showingDeleted: $showingDeleted,
                    failure: restoreFailure,
                    onRestore: restore
                )
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .background(AmbientBackground())
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $settlingTransfer) { presentation in
            SettleUpSheet(ledger: ledger, userId: userId, groupId: groupId,
                          transfer: presentation.transfer, payees: payees)
                .presentationDetents([.medium])
        }
        .sheet(item: $auditingMember) { memberId in
            BalanceAuditSheet(ledger: ledger, userId: userId, groupId: groupId, memberId: memberId)
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $viewingExpense) { expenseId in
            ExpenseDetailSheet(ledger: ledger, userId: userId, groupId: groupId, expenseId: expenseId)
                .presentationDragIndicator(.visible)
        }
    }

    private func restore(_ expenseId: ExpenseID) {
        do {
            try ledger.record(.expenseRestored(EmptyPayload()), entityId: expenseId.rawValue, in: groupId)
            restoreFailure = nil
        } catch {
            restoreFailure = String(describing: error)
        }
    }
}

/// `SuggestedTransfer` is a plain Core value; wrap it for `.sheet(item:)`.
private struct TransferPresentation: Identifiable {
    let id = UUID()
    let transfer: SuggestedTransfer
}

// MARK: - Balance card

private struct GroupBalanceCard: View {
    let group: GroupState
    let userId: UserID

    var body: some View {
        let net = group.net(for: userId)
        let direction = BalanceDirection(net.amountMinor)
        VStack(alignment: .leading, spacing: 0) {
            Text("Din balans").font(.subheadline).foregroundStyle(Theme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SignedAmountText(
                    amountMinor: net.amountMinor,
                    currency: net.currency,
                    size: 30,
                    accessibilityPhrase: "\(direction.spokenWord) \(MoneyFormat.string(abs(net.amountMinor), net.currency))"
                )
                Text(direction.word).font(.footnote).foregroundStyle(Theme.secondary)
            }
            .padding(.top, 2)
            ZeroLine(amountMinor: net.amountMinor, scaleMinor: scale)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// The largest balance magnitude in the group, so every member's bar reads on one scale.
    private var scale: Int64 {
        group.balances().byMember.values.map { abs($0) }.max() ?? 0
    }
}

// MARK: - Vem är skyldig vem

private struct TransfersCard: View {
    let group: GroupState
    let meId: MemberID?
    let onSettle: (SuggestedTransfer) -> Void
    let onAudit: (MemberID) -> Void

    var body: some View {
        let transfers = group.suggestedTransfers()
        if transfers.isEmpty {
            SectionHeader(title: String(localized: "Vem är skyldig vem"))
            Text("Alla är kvitt 🎉")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity)
                .cardSurface()
        } else {
            SectionHeader(title: String(localized: "Vem är skyldig vem"))
            VStack(spacing: 0) {
                ForEach(Array(transfers.enumerated()), id: \.offset) { index, transfer in
                    if index > 0 {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                    TransferRow(
                        group: group,
                        meId: meId,
                        transfer: transfer,
                        onSettle: { onSettle(transfer) },
                        onAudit: { onAudit(counterparty(of: transfer)) }
                    )
                }
            }
            .cardSurface(padding: 6)
        }
    }

    /// Who a tapped transfer should explain: the person on the other side of it from you —
    /// or the debtor when the transfer is between two others.
    private func counterparty(of transfer: SuggestedTransfer) -> MemberID {
        transfer.from == meId ? transfer.to : transfer.from
    }
}

private struct TransferRow: View {
    let group: GroupState
    let meId: MemberID?
    let transfer: SuggestedTransfer
    let onSettle: () -> Void
    let onAudit: () -> Void

    var body: some View {
        HStack {
            // The row body opens the audit; the trailing button settles. Two separate targets,
            // matching "tap any balance/transfer" from the design doc's trust rule.
            Button(action: onAudit) {
                HStack {
                    (Text(name(transfer.from)) + Text(verbatim: " → ") + Text(name(transfer.to)))
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                    SignedAmountText(
                        amountMinor: transfer.amountMinor,
                        currency: group.currency,
                        size: 15,
                        sign: .none,
                        accessibilityPhrase: spokenPhrase
                    )
                    Spacer(minLength: 8)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button("Gör upp", action: onSettle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.espresso)
                .buttonStyle(.glass)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenPhrase)
    }

    private func name(_ memberId: MemberID) -> String {
        if memberId == meId { return String(localized: "Du") }
        return group.members[memberId]?.displayName ?? "?"
    }

    private var spokenPhrase: String {
        "\(name(transfer.from)) → \(name(transfer.to)), \(MoneyFormat.string(transfer.amountMinor, group.currency))"
    }
}

// MARK: - Expense list

private struct ExpenseList: View {
    let group: GroupState
    let meId: MemberID?
    let onSelect: (ExpenseID) -> Void

    var body: some View {
        // visibleExpenses is already newest-first; chunk into months preserving that order.
        let months = MonthGroup.group(group.visibleExpenses)
        ForEach(months) { month in
            SectionHeader(title: month.title)
            VStack(spacing: 0) {
                ForEach(Array(month.expenses.enumerated()), id: \.element.id) { index, expense in
                    if index > 0 {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                    Button {
                        onSelect(expense.id)
                    } label: {
                        ExpenseRow(group: group, meId: meId, expense: expense)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .cardSurface(padding: 6)
        }
    }
}

/// The recovery half of soft delete. Hidden entirely until the group has deleted expenses;
/// restoring writes an `ExpenseRestored` and the row rejoins the list above.
private struct DeletedExpensesSection: View {
    let group: GroupState
    @Binding var showingDeleted: Bool
    let failure: String?
    let onRestore: (ExpenseID) -> Void

    var body: some View {
        let deleted = group.deletedExpenses
        if !deleted.isEmpty {
            Button {
                withAnimation { showingDeleted.toggle() }
            } label: {
                Text(showingDeleted ? "Dölj borttagna" : "Visa borttagna (\(deleted.count))")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 4)

            if showingDeleted {
                VStack(spacing: 0) {
                    ForEach(Array(deleted.enumerated()), id: \.element.id) { index, expense in
                        if index > 0 {
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                        }
                        HStack {
                            Text(expense.title)
                                .font(.subheadline)
                                .strikethrough()
                                .foregroundStyle(Theme.secondary)
                            Spacer()
                            NeutralAmountText(
                                amountMinor: expense.amountMinor,
                                currency: expense.currency,
                                size: 14
                            )
                            .foregroundStyle(Theme.secondary)
                            Button("Återställ") { onRestore(expense.id) }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.espresso)
                                .buttonStyle(.glass)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
                .cardSurface(padding: 6)

                if let failure {
                    Text(failure).font(.footnote).foregroundStyle(Theme.clay)
                }
            }
        }
    }
}

/// One month's worth of expenses, newest month first.
private struct MonthGroup: Identifiable {
    let id: String
    let title: String
    let expenses: [Expense]

    static func group(_ expenses: [Expense]) -> [MonthGroup] {
        var order: [String] = []
        var byMonth: [String: [Expense]] = [:]
        for expense in expenses {
            let key = "\(expense.date.year)-\(expense.date.month)"
            if byMonth[key] == nil { order.append(key) }
            byMonth[key, default: []].append(expense)
        }
        return order.map { key in
            let first = byMonth[key]!.first!
            return MonthGroup(id: key, title: title(for: first.date), expenses: byMonth[key]!)
        }
    }

    /// "Juli" for the current year, "Juli 2025" for older ones. Locale-aware month names.
    private static func title(for date: CalendarDate) -> String {
        let symbols = Calendar.current.standaloneMonthSymbols
        let name = (1...12).contains(date.month) ? symbols[date.month - 1].capitalized : "?"
        let currentYear = CalendarDate(Date()).year
        return date.year == currentYear ? name : "\(name) \(date.year)"
    }
}

private struct ExpenseRow: View {
    let group: GroupState
    let meId: MemberID?
    let expense: Expense

    var body: some View {
        HStack(spacing: 12) {
            Text(Categories.emoji(for: expense.categoryId))
                .font(.system(size: 18))
                .frame(width: 36, height: 36)
                .background(Color(hex: 0xF5EBDD), in: .circle)

            VStack(alignment: .leading, spacing: 1) {
                Text(expense.title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                Text(payerLine).font(.footnote).foregroundStyle(Theme.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                NeutralAmountText(
                    amountMinor: expense.amountMinor,
                    currency: expense.currency,
                    size: 16
                )
                if let meId {
                    Text("din del \(MoneyFormat.string(expense.payload.share(of: meId), expense.currency))")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var payerLine: String {
        let payers = expense.payload.payers
        guard let first = payers.first else { return "" }
        let name = first.memberId == meId
            ? String(localized: "Du")
            : group.members[first.memberId]?.displayName ?? "?"
        return payers.count == 1
            ? String(localized: "\(name) betalade")
            : String(localized: "\(name) med flera betalade")
    }
}

// MARK: - Shared

/// The uppercase warm-grey section label from the mockup. Takes a resolved string; localizable
/// callers pass `String(localized:)`, computed ones (month names) pass the value directly.
private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .kerning(0.5)
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 6)
            .padding(.top, 8)
    }
}
