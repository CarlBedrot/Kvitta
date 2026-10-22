import SwiftUI
import KvittaCore

/// UTGIFTER (08): expenses by month, newest month and newest expense first, plus the soft-deleted
/// ones tucked away at the bottom. The only read path — every card comes straight out of
/// `group.visibleExpenses`.
struct GroupExpensesTab: View {
    let group: GroupState
    let meId: MemberID?
    let mode: CurrencyDisplay
    let canSplit: Bool
    let onSelect: (ExpenseID) -> Void
    let onInvite: () -> Void
    let onAddExpense: () -> Void
    @Binding var showingDeleted: Bool
    let restoreFailure: String?
    let onRestore: (ExpenseID) -> Void

    /// `.only` narrows the list to one currency; native and ≈ modes always show every expense in
    /// its own currency — an expense is a fact, and facts do not convert (same rule the old list used).
    private var visible: [Expense] {
        if case .only(let currency) = mode {
            return group.visibleExpenses.filter { $0.currency == currency }
        }
        return group.visibleExpenses
    }

    var body: some View {
        if visible.isEmpty {
            EmptyExpenses(canSplit: canSplit, onInvite: onInvite, onAddExpense: onAddExpense)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(ExpenseMonthGroup.group(visible)) { month in
                    Steven.SectionHeader(verbatim: month.title)
                    LazyVStack(spacing: StevenMetric.cardGap) {
                        ForEach(month.expenses) { expense in
                            Button { onSelect(expense.id) } label: {
                                ExpenseCard(group: group, meId: meId, expense: expense)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, StevenMetric.gutter)
                    .padding(.top, 12)
                }
            }
        }
        DeletedExpensesSection(
            group: group, showingDeleted: $showingDeleted, failure: restoreFailure, onRestore: onRestore
        )
    }
}

/// "Inga utgifter än" (§1.2, marked [gissning] in the reference): a brand-new group can only
/// invite (nobody to split with yet); one with friends already in it can add the first expense —
/// the same fork the old hero card offered before Steven took its place.
private struct EmptyExpenses: View {
    let canSplit: Bool
    let onInvite: () -> Void
    let onAddExpense: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Inga utgifter än")
                .stevenFont(.rowTitle)
                .foregroundStyle(StevenColor.muted)
            if canSplit {
                Button("Lägg till utgift", action: onAddExpense)
                    .buttonStyle(Steven.FilledButtonStyle(height: StevenMetric.compactButtonHeight))
                    .fixedSize()
            } else {
                Button("Bjud in", action: onInvite)
                    .buttonStyle(Steven.FilledButtonStyle(height: StevenMetric.compactButtonHeight))
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

/// One expense card (08): a tonal receipt icon, title, date, amount, and a footer saying who was
/// in on it and who paid. The icon's tint follows the payer, never the category — the reference
/// draws the same receipt glyph on every card (README §2.4).
struct ExpenseCard: View {
    let group: GroupState
    let meId: MemberID?
    let expense: Expense

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.plaintext")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(StevenColor.ink)
                .frame(width: StevenMetric.iconCircle, height: StevenMetric.iconCircle)
                .background(iDidPay ? StevenColor.accentTint : StevenColor.oweTint, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(expense.title).stevenFont(.rowTitleBold).foregroundStyle(StevenColor.ink).lineLimit(1)
                    Spacer(minLength: 8)
                    Steven.MoneyText(amountMinor: expense.amountMinor, currency: expense.currency,
                                     explicit: expense.currency != group.currency)
                }
                Text(verbatim: dateLabel).stevenFont(.footnote).foregroundStyle(StevenColor.muted)
                HStack {
                    Text(verbatim: friendsLabel).stevenFont(.footnoteBold).foregroundStyle(StevenColor.faint)
                    Spacer(minLength: 8)
                    Text(verbatim: payerLabel).stevenFont(.footnoteBold).foregroundStyle(StevenColor.faint)
                }
            }
        }
        .padding(StevenMetric.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stevenCardBackground()
        .accessibilityElement(children: .combine)
    }

    private var iDidPay: Bool {
        guard let meId else { return false }
        return expense.payload.payers.contains { $0.memberId == meId }
    }

    private var dateLabel: String {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let instant = Date(timeIntervalSince1970: Double(expense.date.dayNumber) * 86_400)
        let weekday = calendar.weekdaySymbols[calendar.component(.weekday, from: instant) - 1]
        let month = calendar.shortStandaloneMonthSymbols[expense.date.month - 1]
        return "\(weekday), \(expense.date.day) \(month)"
    }

    /// "Du och N vän(ner)" when you took part, otherwise "N vänner" for everyone else.
    private var friendsLabel: String {
        let involved = expense.payload.involvedMembers
        if let meId, involved.contains(meId) {
            return String(localized: "Du och \(involved.count - 1) vänner")
        }
        return String(localized: "\(involved.count) vänner")
    }

    private var payerLabel: String {
        guard let first = expense.payload.payers.first else { return "" }
        let name = first.memberId == meId
            ? String(localized: "Du")
            : group.members[first.memberId]?.displayName ?? "?"
        return expense.payload.payers.count == 1
            ? String(localized: "\(name) betalade")
            : String(localized: "\(name) med flera betalade")
    }
}

/// One month's expenses, newest first — always "MÅN. ÅÅÅÅ" (the reference shows the year even
/// for the current month, unlike the year-omitting label the old list used).
struct ExpenseMonthGroup: Identifiable {
    let id: String
    let title: String
    let expenses: [Expense]

    static func group(_ expenses: [Expense]) -> [ExpenseMonthGroup] {
        var order: [String] = []
        var byMonth: [String: [Expense]] = [:]
        for expense in expenses {
            let key = "\(expense.date.year)-\(expense.date.month)"
            if byMonth[key] == nil { order.append(key) }
            byMonth[key, default: []].append(expense)
        }
        return order.map { key in
            let first = byMonth[key]!.first!
            return ExpenseMonthGroup(id: key, title: title(for: first.date), expenses: byMonth[key]!)
        }
    }

    private static func title(for date: CalendarDate) -> String {
        let symbols = Calendar.current.shortStandaloneMonthSymbols
        let name = (1...12).contains(date.month) ? symbols[date.month - 1] : "?"
        return "\(name) \(date.year)"
    }
}

/// The recovery half of soft delete, restyled for Steven. Hidden entirely until the group has
/// deleted expenses; restoring writes an `ExpenseRestored` and the row rejoins the list above.
struct DeletedExpensesSection: View {
    let group: GroupState
    @Binding var showingDeleted: Bool
    let failure: String?
    let onRestore: (ExpenseID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let deleted = group.deletedExpenses
        if !deleted.isEmpty {
            Button {
                withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { showingDeleted.toggle() }
            } label: {
                Text(showingDeleted ? "Dölj borttagna" : "Visa borttagna (\(deleted.count))")
                    .stevenFont(.footnoteBold)
                    .foregroundStyle(StevenColor.muted)
                    .frame(maxWidth: .infinity, minHeight: StevenMetric.minimumHitTarget)
            }
            .padding(.top, 8)

            if showingDeleted {
                Steven.Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(deleted.enumerated()), id: \.element.id) { index, expense in
                            if index > 0 { Steven.Hairline(color: StevenColor.rowSeparator) }
                            deletedRow(expense)
                        }
                    }
                }
                .padding(.horizontal, StevenMetric.gutter)

                if let failure {
                    Text(verbatim: failure).stevenFont(.footnote).foregroundStyle(StevenColor.owe)
                        .padding(.horizontal, StevenMetric.gutter)
                }
            }
        }
    }

    private func deletedRow(_ expense: Expense) -> some View {
        HStack {
            Text(expense.title).stevenFont(.rowTitle).strikethrough().foregroundStyle(StevenColor.muted)
            Spacer()
            Steven.MoneyText(amountMinor: expense.amountMinor, currency: expense.currency, tone: .muted)
            Button("Återställ") { onRestore(expense.id) }
                .stevenFont(.footnoteBold)
                .foregroundStyle(StevenColor.accent)
        }
        .padding(.horizontal, StevenMetric.gutter)
        .padding(.vertical, 10)
    }
}
