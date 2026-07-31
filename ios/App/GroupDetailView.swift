import SwiftUI
import KvittaCore
import KvittaStorage

/// Gruppvy: the hero balance, who owes whom, the members, and the expense list by month.
///
/// Everything here is a read of the projection — `balances()`, `suggestedTransfers()`,
/// `visibleExpenses` — plus one write path: a transfer's "Gör upp" opens `SettleUpSheet`, which
/// records a `PaymentRecorded` through `LedgerStore.record`.
struct GroupDetailView: View {
    let ledger: LedgerStore
    let userId: UserID
    let groupId: GroupID
    var payees = PayeeDirectory()
    let invites: InviteModel
    let profile: UserProfile

    @State private var settlingTransfer: TransferPresentation?
    @State private var auditingMember: MemberID?
    @State private var viewingExpense: ExpenseID?
    @State private var showingDeleted = false
    @State private var restoreFailure: String?
    @State private var showingMembers = false
    /// Adding an expense from inside the group it belongs to — the group is the screen you are
    /// standing on, so there is nothing to guess.
    @State private var expenseModel: NewExpenseModel?

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
        let canSplit = group.activeMembers.count >= 2
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // The trust rule (product principles): every balance on screen opens the exact
                // lines behind it. The card audits you; a member row audits that member.
                Button {
                    if let meId { auditingMember = meId }
                } label: {
                    GroupHeroCard(group: group, userId: userId)
                }
                .buttonStyle(ScaleButtonStyle())

                if !canSplit {
                    SoloGroupCard { showingMembers = true }
                }

                if canSplit {
                    QuickActionsCard(
                        onAddExpense: {
                            expenseModel = NewExpenseModel(ledger: ledger, userId: userId, groupId: groupId)
                        },
                        onMembers: { showingMembers = true }
                    )
                }

                TransfersCard(
                    group: group,
                    meId: meId,
                    onSettle: { settlingTransfer = TransferPresentation(transfer: $0) },
                    onAudit: { auditingMember = $0 }
                )

                MembersCard(group: group, meId: meId) { auditingMember = $0 }

                ExpenseList(group: group, meId: meId) { viewingExpense = $0 }
                DeletedExpensesSection(
                    group: group,
                    showingDeleted: $showingDeleted,
                    failure: restoreFailure,
                    onRestore: restore
                )
                Color.clear.frame(height: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .background(AmbientBackground())
        .navigationTitle(GroupBadge.title(of: group.name))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingMembers = true
                } label: {
                    Label("Medlemmar", systemImage: "person.2")
                }
            }
        }
        .sheet(isPresented: $showingMembers) {
            MembersSheet(ledger: ledger, userId: userId, groupId: groupId, invites: invites)
        }
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $settlingTransfer) { presentation in
            SettleUpSheet(ledger: ledger, userId: userId, groupId: groupId,
                          transfer: presentation.transfer, payees: payees, profile: profile)
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
        .sheet(item: $expenseModel) { model in
            NewExpenseSheet(model: model)
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

// MARK: - Hero

/// Your position in this group: the sentence, the number large, and how much of the group is
/// already settled. Settled gets the green celebration instead of a zero.
private struct GroupHeroCard: View {
    let group: GroupState
    let userId: UserID

    var body: some View {
        let net = group.net(for: userId)
        if group.balances().byMember.values.allSatisfy({ $0 == 0 }) {
            settled
        } else {
            open(net: net)
        }
    }

    private var settled: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ni är kvitt 🎉")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("Ingen i gruppen är skyldig någon något.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Theme.positiveWash, in: .rect(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }

    private func open(net: Money) -> some View {
        let direction = BalanceDirection(net.amountMinor)
        let members = group.activeMembers.count
        let settledMembers = group.balances().byMember.values.filter { $0 == 0 }.count
        return VStack(alignment: .leading, spacing: 8) {
            Text(direction == .owe ? "Du är skyldig" : (direction == .owed ? "Du ligger ute med" : "Din balans"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.secondary)

            SignedAmountText(
                amountMinor: net.amountMinor,
                currency: net.currency,
                size: 40,
                sign: direction == .settled ? .always : .none,
                accessibilityPhrase: "\(direction.spokenWord) \(MoneyFormat.string(abs(net.amountMinor), net.currency))"
            )
            .contentTransition(.numericText())

            SettleProgressBar(
                fraction: members == 0 ? 0 : Double(settledMembers) / Double(members),
                tint: Theme.tint(forSign: net.amountMinor)
            )
            .padding(.top, 8)

            Text("\(settledMembers) av \(members) är kvitt")
                .font(.caption)
                .foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 24)
    }
}

// MARK: - A group of one

/// What a brand-new group shows instead of an expense button.
///
/// A group is created with only you in it now, so this is the state every group passes through.
/// It points at one place — Medlemmar — because that screen already holds both ways forward: the
/// invite link, and adding somebody by name for the friend who will never install anything.
private struct SoloGroupCard: View {
    let onOpenMembers: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bara du i gruppen än")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("Bjud in de andra med en länk, eller lägg till dem som namn om de inte tänker skaffa appen.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
            Button("Lägg till eller bjud in", action: onOpenMembers)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

// MARK: - Snabbfunktioner

/// The two things people come to a group screen to do, as named rows — the mockup's quick
/// actions. Settling is deliberately not here: a payment belongs to a specific transfer, and
/// those have their own "Gör upp" buttons just below.
private struct QuickActionsCard: View {
    let onAddExpense: () -> Void
    let onMembers: () -> Void

    var body: some View {
        SectionHeader(title: String(localized: "Snabbfunktioner"))
        VStack(spacing: 0) {
            QuickActionRow(title: "Lägg till utgift", systemImage: "receipt", action: onAddExpense)
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 64)
            QuickActionRow(title: "Medlemmar och inbjudan", systemImage: "person.badge.plus", action: onMembers)
        }
        .cardSurface(padding: 8)
    }
}

private struct QuickActionRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                IconBadge(systemImage: systemImage, size: 36)
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(ScaleButtonStyle())
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
        if !transfers.isEmpty {
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
            .cardSurface(padding: 8)
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
                HStack(spacing: 6) {
                    (Text(name(transfer.from)) + Text(verbatim: " → ") + Text(name(transfer.to)))
                        .font(.subheadline.weight(.medium))
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
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.accent, in: .rect(cornerRadius: 18))
                .buttonStyle(ScaleButtonStyle())
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

// MARK: - Medlemmar

/// Everyone in the group with where they stand, the mockup's member list. Tapping a row opens
/// the audit for that member — same trust rule as everywhere else.
private struct MembersCard: View {
    let group: GroupState
    let meId: MemberID?
    let onAudit: (MemberID) -> Void

    var body: some View {
        let balances = group.balances().byMember
        let members = group.activeMembers.sorted { left, right in
            // You first, then by name — the mockup's order, and the one people scan for.
            if left.id == meId { return true }
            if right.id == meId { return false }
            return left.displayName < right.displayName
        }
        SectionHeader(title: String(localized: "Medlemmar"))
        VStack(spacing: 0) {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                if index > 0 {
                    Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 62)
                }
                Button {
                    onAudit(member.id)
                } label: {
                    HStack(spacing: 14) {
                        Avatar(name: member.displayName, size: 36)
                        Text(member.id == meId ? String(localized: "Du") : member.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        SignedAmountText(
                            amountMinor: balances[member.id] ?? 0,
                            currency: group.currency,
                            size: 15,
                            accessibilityPhrase: "\(member.displayName): \(BalanceDirection(balances[member.id] ?? 0).spokenWord) \(MoneyFormat.string(abs(balances[member.id] ?? 0), group.currency))"
                        )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(.rect)
                }
                .buttonStyle(ScaleButtonStyle())
            }
        }
        .cardSurface(padding: 8)
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
                        Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 62)
                    }
                    Button {
                        onSelect(expense.id)
                    } label: {
                        ExpenseRow(group: group, meId: meId, expense: expense)
                            .contentShape(.rect)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .cardSurface(padding: 8)
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
                withAnimation(.spring(duration: 0.3)) { showingDeleted.toggle() }
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
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                }
                .cardSurface(padding: 8)

                if let failure {
                    Text(failure).font(.footnote).foregroundStyle(Theme.negative)
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
        HStack(spacing: 14) {
            Text(Categories.emoji(for: expense.categoryId))
                .font(.system(size: 17))
                .frame(width: 36, height: 36)
                .background(Theme.accent.opacity(0.08), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                Text(payerLine).font(.caption).foregroundStyle(Theme.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
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
        let paid = payers.count == 1
            ? String(localized: "\(name) betalade")
            : String(localized: "\(name) med flera betalade")
        // The day, so a row is placed in time without opening it. The month header carries the
        // month; this carries the date within it.
        return "\(paid) · \(expense.date.day)/\(expense.date.month)"
    }
}

// MARK: - Shared

/// The small warm-grey section label. Takes a resolved string; localizable callers pass
/// `String(localized:)`, computed ones (month names) pass the value directly.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .kerning(0.5)
            .foregroundStyle(Theme.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, 12)
    }
}
