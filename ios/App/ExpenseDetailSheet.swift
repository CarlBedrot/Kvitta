import SwiftUI
import KvittaCore
import KvittaStorage

/// Utgiftsdetalj (15): the payer's face and the sentence, when it was created and last edited,
/// and the shares everyone carries. The only write actions here are "Ändra", which opens the
/// expense for editing, and the editor itself (soft delete lives there — see `NewExpenseSheet`).
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

    private var group: GroupState? { ledger.state[groupId] }
    private var expense: Expense? { group?.expenses[expenseId] }

    var body: some View {
        VStack(spacing: 0) {
            Steven.NavTitleBar(leading: .close({ dismiss() }), trailing: trailing) {
                Text(verbatim: expense?.title ?? "")
            }
            if let group, let expense {
                content(group: group, expense: expense)
            } else {
                ContentUnavailableView("Utgiften finns inte längre", systemImage: "questionmark.circle")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(StevenColor.surface, ignoresSafeAreaEdges: .top)
        .sheet(item: $editModel) { model in
            NewExpenseSheet(model: model)
                .presentationDragIndicator(.visible)
        }
    }

    private var trailing: Steven.NavTrailing {
        guard let expense else { return .none }
        return .text("Ändra", { startEditing(expense) })
    }

    private func startEditing(_ expense: Expense) {
        editModel = NewExpenseModel(ledger: ledger, userId: userId, groupId: groupId, editing: expense)
    }

    private func content(group: GroupState, expense: Expense) -> some View {
        let meId = group.me(for: userId)?.id
        return ScrollView {
            VStack(spacing: 0) {
                PayerSummary(group: group, meId: meId, expense: expense)
                ParticipantsSection(group: group, meId: meId, expense: expense)
                Footnote(group: group, expense: expense)
            }
            .padding(.bottom, 26)
        }
    }
}

// MARK: - Payer summary

/// The avatar, the "Carl betalade **368 kr**" / "för Køben" sentence, and the date — all
/// centered (15).
private struct PayerSummary: View {
    let group: GroupState
    let meId: MemberID?
    let expense: Expense

    private var payer: MoneyLine? { expense.payload.payers.first }

    var body: some View {
        VStack(spacing: 8) {
            // `payer` is only ever empty for a malformed expense the write-side invariant (every
            // expense sums to a positive amount across at least one payer) should never produce —
            // the expense's own id just keeps the pastel plate stable if it somehow does.
            Steven.AvatarView(name: payerName, id: payer?.memberId ?? MemberID(rawValue: expense.id.rawValue),
                               size: StevenMetric.avatarHero, isMe: payer?.memberId == meId)
            PayerSentence(payerName: payerName, amountMinor: payer?.amountMinor ?? expense.amountMinor,
                          currency: expense.currency)
            Text(String(localized: "för \(expense.title)"))
                .stevenFont(.sentence)
                .foregroundStyle(StevenColor.ink)
                .multilineTextAlignment(.center)
            Text(verbatim: StevenExpenseDate.detailLine(expense.date))
                .stevenFont(.rowTitle)
                .foregroundStyle(StevenColor.muted)
                .padding(.top, 4)
        }
        .padding(.horizontal, StevenMetric.gutter)
        .padding(.top, 32)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
    }

    private var payerName: String {
        guard let payer else { return "?" }
        if payer.memberId == meId { return String(localized: "Du") }
        return firstName(of: group.members[payer.memberId]?.displayName ?? "?")
    }
}

/// "Carl betalade **368 kr**": one `Text` run so the bold amount sits inline with the regular
/// words. `stevenFont` can't build it — it returns `some View`, not `Text`, and only `Text` can
/// be concatenated with `+` — so this reads `StevenFont.sentence`'s own size and weight directly.
private struct PayerSentence: View {
    let payerName: String
    let amountMinor: Int64
    let currency: CurrencyCode

    @ScaledMetric(relativeTo: StevenFont.sentence.textStyle) private var size: CGFloat = StevenFont.sentence.size

    var body: some View {
        (regular + bold)
            .multilineTextAlignment(.center)
            .foregroundStyle(StevenColor.ink)
    }

    private var regular: Text {
        Text(verbatim: String(localized: "\(payerName) betalade") + " ")
            .font(.system(size: size, weight: StevenFont.sentence.weight))
    }

    private var bold: Text {
        Text(verbatim: StevenMoneyFormat.string(amountMinor, currency))
            .font(.system(size: size, weight: .bold))
            .monospacedDigit()
    }
}

// MARK: - Participants

/// "Deltagare" and one row per share (15). Sentence case, not the all-caps `SectionHeader` the
/// rest of the app uses for section titles — the reference image shows it lowercase.
private struct ParticipantsSection: View {
    let group: GroupState
    let meId: MemberID?
    let expense: Expense

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Deltagare")
                .stevenFont(.footnote)
                .foregroundStyle(StevenColor.muted)
                .padding(.horizontal, StevenMetric.gutter)
                .padding(.top, 20)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            Steven.Hairline()
            ForEach(expense.payload.shares, id: \.memberId) { share in
                ParticipantRow(name: name(of: share.memberId), memberId: share.memberId,
                                isMe: share.memberId == meId,
                                amountMinor: share.amountMinor, currency: expense.currency)
            }
        }
    }

    private func name(of memberId: MemberID) -> String {
        if memberId == meId { return String(localized: "Du") }
        return firstName(of: group.members[memberId]?.displayName ?? "?")
    }
}

/// One participant: avatar 40, first name, their share in grey (15).
private struct ParticipantRow: View {
    let name: String
    let memberId: MemberID
    let isMe: Bool
    let amountMinor: Int64
    let currency: CurrencyCode

    var body: some View {
        HStack(spacing: 16) {
            Steven.AvatarView(name: name, id: memberId, size: StevenMetric.avatarRow, isMe: isMe)
            Text(verbatim: name).stevenFont(.rowTitle).foregroundStyle(StevenColor.ink)
            Spacer(minLength: 8)
            Steven.MoneyText(amountMinor: amountMinor, currency: currency, font: .rowTitle, tone: .muted)
        }
        .padding(.horizontal, StevenMetric.gutter)
        .frame(minHeight: StevenMetric.rowHeight)
        .overlay(alignment: .bottom) { Steven.Hairline(color: StevenColor.rowSeparator) }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Footnote

/// "Utgift skapad manuellt, av Carl Bedrot, 19 okt., 2026, 16:40" (+ a second line once edited),
/// straight off the projected entity — the full event-by-event history belongs to a later round
/// once the store exposes per-entity event queries.
private struct Footnote: View {
    let group: GroupState
    let expense: Expense

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: created)
            if expense.wasEdited {
                Text(verbatim: edited)
            }
        }
        .stevenFont(.footnote)
        .foregroundStyle(StevenColor.muted)
        .padding(.horizontal, StevenMetric.gutter)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var created: String {
        let when = StevenExpenseDate.footnoteLine(expense.createdAt.date)
        guard let author = author(expense.createdBy) else {
            return String(localized: "Utgift skapad manuellt, \(when)")
        }
        return String(localized: "Utgift skapad manuellt, av \(author), \(when)")
    }

    private var edited: String {
        let when = StevenExpenseDate.footnoteLine(expense.lastModifiedAt.date)
        guard let author = author(expense.lastModifiedBy) else {
            return String(localized: "Ändrad \(when)")
        }
        return String(localized: "Ändrad av \(author), \(when)")
    }

    /// Only linked members are mappable — placeholder members never author events.
    private func author(_ userId: UserID) -> String? {
        group.members.values.first { $0.linkedUserId == userId }?.displayName
    }
}

// MARK: - Shared helpers

/// "Ellen Ekwall" → "Ellen"; a one-word name is left alone.
private func firstName(of name: String) -> String {
    name.split(separator: " ").first.map(String.init) ?? name
}

/// Steven's expense-detail date strings (15): hand-built like `StevenMoneyFormat`, because the
/// comma placement is Steven's own style, not one of `Date.FormatStyle`'s locale defaults.
/// Weekday and month names still come from the current locale, so English keeps reading in words.
enum StevenExpenseDate {
    /// "måndag 19, okt. 2026" — the sentence's date line.
    static func detailLine(_ date: CalendarDate) -> String {
        var components = DateComponents()
        components.year = date.year
        components.month = date.month
        components.day = date.day
        guard let resolved = Calendar.current.date(from: components) else { return date.iso8601 }
        let weekday = Calendar.current.weekdaySymbols[Calendar.current.component(.weekday, from: resolved) - 1]
        let month = resolved.formatted(.dateTime.month(.abbreviated))
        return "\(weekday) \(date.day), \(month) \(date.year)"
    }

    /// "19 okt., 2026, 16:40" — the footnote timestamp.
    static func footnoteLine(_ date: Date) -> String {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        let year = calendar.component(.year, from: date)
        let month = date.formatted(.dateTime.month(.abbreviated))
        let time = date.formatted(.dateTime.hour().minute())
        return "\(day) \(month), \(year), \(time)"
    }
}
