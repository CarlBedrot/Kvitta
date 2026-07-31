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

    var body: some View {
        let days = DayGroup.build(from: ledger.state, userId: userId)
        Group {
            if days.isEmpty {
                ContentUnavailableView {
                    Label("Ingen aktivitet än", systemImage: "arrow.triangle.2.circlepath")
                } description: {
                    Text("Utgifter och betalningar dyker upp här.")
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(days) { day in
                            SectionHeader(title: day.title)
                            VStack(spacing: 0) {
                                ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                                    if index > 0 {
                                        Rectangle().fill(Theme.hairline).frame(height: 1)
                                            .padding(.leading, 62)
                                    }
                                    FeedRow(entry: entry)
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

    var body: some View {
        HStack(spacing: 14) {
            icon

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
