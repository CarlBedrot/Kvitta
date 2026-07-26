import SwiftUI
import KvittaCore
import KvittaStorage

/// Aktivitet: the chronological cross-group feed, newest first.
///
/// Derived entirely from the projection — one entry per visible expense and payment, ordered by
/// when this device recorded them. Edits surface as a "redigerad" tag on the expense's row rather
/// than separate feed entries; the full event history belongs to Utgiftsdetalj.
struct ActivityView: View {
    let ledger: LedgerStore
    let userId: UserID

    var body: some View {
        let entries = FeedEntry.build(from: ledger.state, userId: userId)
        Group {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("Ingen aktivitet än", systemImage: "arrow.triangle.2.circlepath")
                } description: {
                    Text("Utgifter och betalningar dyker upp här.")
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                Rectangle().fill(Theme.hairline).frame(height: 1)
                            }
                            FeedRow(entry: entry)
                        }
                    }
                    .cardSurface(padding: 6)
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    Color.clear.frame(height: 120)
                }
            }
        }
        .background(AmbientBackground())
        .navigationTitle("Aktivitet")
    }
}

/// One feed line, precomputed so the row view just renders strings.
private struct FeedEntry: Identifiable {
    let id: UUID
    let timestamp: Timestamp
    let emoji: String
    let title: String
    let subtitle: String
    let amountMinor: Int64
    let currency: CurrencyCode
    let wasEdited: Bool

    static func build(from state: LedgerState, userId: UserID) -> [FeedEntry] {
        var entries: [FeedEntry] = []

        for group in state.groups.values {
            let meId = group.me(for: userId)?.id

            func displayName(_ memberId: MemberID) -> String {
                if memberId == meId { return String(localized: "Du") }
                return group.members[memberId]?.displayName ?? "?"
            }

            for expense in group.visibleExpenses {
                let payerName = expense.payload.payers.first.map { displayName($0.memberId) } ?? "?"
                entries.append(FeedEntry(
                    id: expense.id.rawValue,
                    timestamp: expense.lastModifiedAt,
                    emoji: Categories.emoji(for: expense.categoryId),
                    title: expense.title,
                    subtitle: "\(group.name) · \(String(localized: "\(payerName) betalade"))",
                    amountMinor: expense.amountMinor,
                    currency: expense.currency,
                    wasEdited: expense.wasEdited
                ))
            }

            for payment in group.paymentsByDate {
                entries.append(FeedEntry(
                    id: payment.id.rawValue,
                    timestamp: payment.recordedAt,
                    emoji: "🤝",
                    title: String(localized: "\(displayName(payment.fromMemberId)) betalade \(displayName(payment.toMemberId))"),
                    subtitle: group.name,
                    amountMinor: payment.amountMinor,
                    currency: payment.currency,
                    wasEdited: false
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

private struct FeedRow: View {
    let entry: FeedEntry

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.emoji)
                .font(.system(size: 18))
                .frame(width: 36, height: 36)
                .background(Color(hex: 0xF5EBDD), in: .circle)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                    if entry.wasEdited {
                        Text("redigerad")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .overlay(Capsule().stroke(Theme.hairline))
                    }
                }
                Text(entry.subtitle).font(.footnote).foregroundStyle(Theme.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                NeutralAmountText(
                    amountMinor: entry.amountMinor,
                    currency: entry.currency,
                    size: 16
                )
                Text(entry.timestamp.date, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}
