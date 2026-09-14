import SwiftUI
import KvittaCore
import KvittaStorage

/// Notiser: what other people did that touches you, newest first, grouped by day — Idag, Igår,
/// then dates. An expense somebody else put you on, a payment to or from you. Your own actions
/// are not news to you and are left out; everything else in the ledger is on the group screen.
///
/// Derived entirely from the projection. Edits surface as a "redigerad" tag on the expense's row
/// rather than separate entries; the full event history belongs to Utgiftsdetalj.
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

    var body: some View {
        let days = DayGroup.build(from: ledger.state, userId: userId)
        Group {
            if days.isEmpty {
                ContentUnavailableView {
                    Label("Inga notiser än", systemImage: "bell")
                }
            } else {
                ScrollView {
                    // Lazy: the feed spans every group's history, and only the visible days
                    // need rows built.
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(days) { day in
                            SectionHeader(title: day.title)
                            LazyVStack(spacing: 0) {
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
        .navigationTitle("Notiser")
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

}

/// One feed line, precomputed so the row view just renders strings.
struct FeedEntry: Identifiable {
    enum Kind {
        case expense
        /// A repayment. Drawn differently: a payment is the ledger healing, not a new cost.
        case payment(incoming: Bool?)
    }

    let id: UUID
    let groupId: GroupID
    let timestamp: Timestamp
    let kind: Kind
    /// The expense's category, for its glyph. `nil` on a payment.
    let categoryId: String?
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

            // Somebody else's doing, and you are in it. An expense you added or last edited is
            // not news; one that leaves you out belongs under Utan mig, not here.
            for expense in group.visibleExpenses
            where expense.lastModifiedBy != userId && expense.payload.involves(meId) {
                let payerName = expense.payload.payers.first.map { displayName($0.memberId) } ?? "?"
                entries.append(FeedEntry(
                    id: expense.id.rawValue,
                    groupId: group.id,
                    timestamp: expense.lastModifiedAt,
                    kind: .expense,
                    categoryId: expense.categoryId,
                    title: expense.title,
                    subtitle: "\(groupTitle) · \(String(localized: "\(payerName) betalade"))",
                    amountMinor: expense.amountMinor,
                    currency: expense.currency,
                    explicit: expense.currency != group.currency,
                    wasEdited: expense.wasEdited,
                    paymentStatus: nil
                ))
            }

            for payment in group.paymentsByDate
            where payment.recordedBy != userId && (payment.toMemberId == meId || payment.fromMemberId == meId) {
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
                    categoryId: nil,
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

    static func build(from state: LedgerState, userId: UserID) -> [DayGroup] {
        let entries = FeedEntry.build(from: state, userId: userId)
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
            CategoryGlyph(categoryId: entry.categoryId ?? Categories.fallbackId)
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
