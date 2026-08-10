import SwiftUI
import KvittaCore
import KvittaStorage

/// Aktivitet: the cross-group feed, newest first, grouped by day — Idag, Igår, then dates.
///
/// Derived entirely from the projection — one entry per visible expense and payment, ordered by
/// when this device recorded them. Edits surface as a "redigerad" tag on the expense's row rather
/// than separate feed entries; the full event history belongs to Utgiftsdetalj.
struct ActivityView: View {
    let ledger: LedgerStore
    let userId: UserID
    let unread: UnreadStore

    /// Which rows to draw a dot on, frozen when the screen appeared.
    ///
    /// Held separately from `unread.unread` because that set is emptied the moment the feed is
    /// marked read — and if the rows read it directly, every dot would vanish while the user was
    /// still looking at them. The point of the dot is to show what is new *on this visit*.
    @State private var highlighted: Set<UUID> = []

    /// What kind of rows to show. Per-visit state, deliberately not persisted: a filter you set
    /// last month and forgot about would make the feed quietly lie.
    @State private var kind: FeedKindFilter = .all
    /// One group, or all of them. Also per-visit.
    @State private var groupFilter: GroupID?

    var body: some View {
        let days = DayGroup.build(from: ledger.state, userId: userId, kind: kind, group: groupFilter)
        Group {
            if days.isEmpty && kind == .all && groupFilter == nil {
                ContentUnavailableView {
                    Label("Ingen aktivitet än", systemImage: "arrow.triangle.2.circlepath")
                } description: {
                    Text("Utgifter och betalningar dyker upp här.")
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        filterChips
                        if days.isEmpty {
                            // Filtered to nothing: say so where the rows would be, and keep the
                            // chips on screen so the way back out is obvious.
                            Text("Inget matchar filtret.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                        }
                        ForEach(days) { day in
                            SectionHeader(title: day.title)
                            VStack(spacing: 0) {
                                ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                                    if index > 0 {
                                        Rectangle().fill(Theme.hairline).frame(height: 1)
                                            .padding(.leading, 62)
                                    }
                                    FeedRow(entry: entry, isUnread: highlighted.contains(entry.id))
                                }
                            }
                            .cardSurface(padding: 8)
                        }
                        Color.clear.frame(height: 100)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                }
            }
        }
        .background(AmbientBackground())
        .navigationTitle("Aktivitet")
        // Keyed on the log's size, not just `onAppear`: expenses that arrive while this screen is
        // open would otherwise light the tab badge for a feed the user is looking straight at, and
        // would keep it lit until they navigated away and back.
        .task(id: ledger.state.appliedEventIds.count) {
            // The mark is read before the rows are drawn rather than stamped as "now" afterwards,
            // so an event landing mid-draw is shown again next visit instead of being swallowed.
            let mark = unread.pendingMark(from: ledger)
            // Union rather than assignment: the dots have to survive being marked read, and
            // several arrivals during one visit should all keep theirs.
            highlighted.formUnion(unread.unread)
            unread.markRead(upTo: mark)
        }
    }

    /// The mockup's filter row, now that there is something real to filter.
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FeedKindFilter.allCases, id: \.self) { candidate in
                    FilterChip(title: candidate.title, isOn: kind == candidate) {
                        kind = candidate
                    }
                }

                // One chip that is a menu: groups are an open set, kinds are not.
                Menu {
                    Picker("Grupp", selection: $groupFilter) {
                        Text("Alla grupper").tag(GroupID?.none)
                        ForEach(ledger.state.groupsByLastActivity) { group in
                            Text(GroupBadge.title(of: group.name)).tag(GroupID?.some(group.id))
                        }
                    }
                } label: {
                    FilterChipLabel(
                        title: groupFilter.flatMap { ledger.state[$0].map { GroupBadge.title(of: $0.name) } }
                            ?? String(localized: "Alla grupper"),
                        isOn: groupFilter != nil,
                        chevron: true
                    )
                }
            }
        }
    }
}

enum FeedKindFilter: CaseIterable, Hashable {
    case all, expenses, payments

    var title: String {
        switch self {
        case .all: return String(localized: "Allt")
        case .expenses: return String(localized: "Utgifter")
        case .payments: return String(localized: "Betalningar")
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FilterChipLabel(title: title, isOn: isOn, chevron: false)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

private struct FilterChipLabel: View {
    let title: String
    let isOn: Bool
    let chevron: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            if chevron {
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(isOn ? Color.white : Theme.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isOn ? Theme.accent : Theme.card, in: .rect(cornerRadius: 18))
    }
}

/// One feed line, precomputed so the row view just renders strings.
private struct FeedEntry: Identifiable {
    enum Kind {
        case expense
        /// A repayment. Drawn differently: a payment is the ledger healing, not a new cost.
        case payment(incoming: Bool?)
    }

    let id: UUID
    let groupId: GroupID
    let timestamp: Timestamp
    let kind: Kind
    let emoji: String?
    let title: String
    let subtitle: String
    let amountMinor: Int64
    let currency: CurrencyCode
    /// The kr-collision rule: an amount not in its group's primary currency spells out its code.
    let explicit: Bool
    let wasEdited: Bool
    /// Set for payments only (M8): pending and disputed rows say so, because a payment that is
    /// visible but not yet in the balances would otherwise look like a bug.
    let paymentStatus: PaymentStatus?

    static func build(from state: LedgerState, userId: UserID) -> [FeedEntry] {
        var entries: [FeedEntry] = []

        for group in state.groups.values {
            let meId = group.me(for: userId)?.id
            let groupTitle = GroupBadge.title(of: group.name)

            func displayName(_ memberId: MemberID) -> String {
                if memberId == meId { return String(localized: "Du") }
                return group.members[memberId]?.displayName ?? "?"
            }

            for expense in group.visibleExpenses {
                let payerName = expense.payload.payers.first.map { displayName($0.memberId) } ?? "?"
                entries.append(FeedEntry(
                    id: expense.id.rawValue,
                    groupId: group.id,
                    timestamp: expense.lastModifiedAt,
                    kind: .expense,
                    emoji: Categories.emoji(for: expense.categoryId),
                    title: expense.title,
                    subtitle: "\(groupTitle) · \(String(localized: "\(payerName) betalade"))",
                    amountMinor: expense.amountMinor,
                    currency: expense.currency,
                    explicit: expense.currency != group.currency,
                    wasEdited: expense.wasEdited,
                    paymentStatus: nil
                ))
            }

            for payment in group.paymentsByDate {
                // Colour only when the money touched you: green coming in, red going out.
                // A payment between two others is news, not your money — it stays ink.
                let incoming: Bool? = switch (payment.toMemberId == meId, payment.fromMemberId == meId) {
                case (true, _): true
                case (_, true): false
                default: nil
                }
                entries.append(FeedEntry(
                    id: payment.id.rawValue,
                    groupId: group.id,
                    timestamp: payment.recordedAt,
                    kind: .payment(incoming: incoming),
                    emoji: nil,
                    title: String(localized: "\(displayName(payment.fromMemberId)) betalade \(displayName(payment.toMemberId))"),
                    subtitle: groupTitle,
                    amountMinor: payment.amountMinor,
                    currency: payment.currency,
                    explicit: payment.currency != group.currency,
                    wasEdited: false,
                    paymentStatus: payment.status
                ))
            }
        }

        // Newest first; id as tie-break so two devices with the same log agree on the order.
        return entries.sorted {
            $0.timestamp == $1.timestamp
                ? $0.id.uuidString > $1.id.uuidString
                : $0.timestamp > $1.timestamp
        }
    }
}

/// A day's worth of feed, with the header the mockup shows: Idag, Igår, then the date.
private struct DayGroup: Identifiable {
    let id: String
    let title: String
    let entries: [FeedEntry]

    static func build(
        from state: LedgerState,
        userId: UserID,
        kind: FeedKindFilter = .all,
        group groupFilter: GroupID? = nil
    ) -> [DayGroup] {
        let entries = FeedEntry.build(from: state, userId: userId).filter { entry in
            if let groupFilter, entry.groupId != groupFilter { return false }
            switch (kind, entry.kind) {
            case (.all, _): return true
            case (.expenses, .expense): return true
            case (.payments, .payment): return true
            default: return false
            }
        }
        var order: [String] = []
        var byDay: [String: [FeedEntry]] = [:]
        let calendar = Calendar.current

        for entry in entries {
            let day = calendar.startOfDay(for: entry.timestamp.date)
            let key = day.formatted(.iso8601.year().month().day())
            if byDay[key] == nil { order.append(key) }
            byDay[key, default: []].append(entry)
        }

        return order.map { key in
            let date = calendar.startOfDay(for: byDay[key]!.first!.timestamp.date)
            return DayGroup(id: key, title: title(for: date, calendar: calendar), entries: byDay[key]!)
        }
    }

    private static func title(for day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return String(localized: "Idag") }
        if calendar.isDateInYesterday(day) { return String(localized: "Igår") }
        return day.formatted(.dateTime.day().month(.wide))
    }
}

private struct FeedRow: View {
    let entry: FeedEntry
    /// New since the last time this feed was open, and written by somebody else.
    let isUnread: Bool

    var body: some View {
        HStack(spacing: 14) {
            // The dot rides on the icon rather than taking a column of its own. A leading gutter
            // would push every row 21pt right and leave the day dividers — inset to exactly where
            // the icon starts — pointing at nothing. It is also a dot rather than a bold row or a
            // tinted background: the feed's whole job is that names and amounts line up down the
            // column, and anything that changes one row's weight breaks the scan for its
            // neighbours too.
            icon
                .overlay(alignment: .topTrailing) {
                    if isUnread {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 9, height: 9)
                            // Ringed in the card colour so it reads as sitting on top of the icon
                            // rather than as part of it.
                            .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                            .offset(x: 2, y: -2)
                            .accessibilityLabel("Oläst")
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                    if entry.wasEdited {
                        Text("redigerad")
                            .font(.caption2)
                            .foregroundStyle(Theme.tertiary)
                    }
                    if entry.paymentStatus == .pending {
                        Text("väntar")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    } else if entry.paymentStatus == .disputed {
                        Text("bestriden")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.negative)
                    }
                }
                Text(entry.subtitle).font(.caption).foregroundStyle(Theme.secondary)
            }

            Spacer()

            amount
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        switch entry.kind {
        case .expense:
            Text(entry.emoji ?? "🧾")
                .font(.system(size: 17))
                .frame(width: 36, height: 36)
                .background(Theme.accent.opacity(0.08), in: .circle)
        case .payment:
            // Repayments get the system glyph on green, visually apart from spending.
            IconBadge(systemImage: "arrow.left.arrow.right", tint: Theme.positive, size: 36)
        }
    }

    @ViewBuilder
    private var amount: some View {
        switch entry.kind {
        case .expense:
            NeutralAmountText(amountMinor: entry.amountMinor, currency: entry.currency, size: 16, explicit: entry.explicit)
        case .payment(let incoming):
            switch incoming {
            case .some(true):
                // Money that reached you. The + and the green agree.
                SignedAmountText(amountMinor: entry.amountMinor, currency: entry.currency, size: 16, explicit: entry.explicit)
            case .some(false):
                SignedAmountText(amountMinor: -entry.amountMinor, currency: entry.currency, size: 16, explicit: entry.explicit)
            case .none:
                NeutralAmountText(amountMinor: entry.amountMinor, currency: entry.currency, size: 16, explicit: entry.explicit)
            }
        }
    }
}
