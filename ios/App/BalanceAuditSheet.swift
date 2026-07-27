import SwiftUI
import KvittaCore
import KvittaStorage

/// Balansgranskning — the trust view. Every expense and payment behind one member's balance,
/// oldest first, with a running total whose last line is exactly the number that was tapped.
/// This is what makes a balance auditable rather than a number you have to trust.
///
/// All the arithmetic is `GroupState.breakdown(for:)`; this view only renders it. One deliberate
/// deviation from the mockup: the mockup sketches a pairwise "Din balans med Jonas", but the
/// audited quantity in this app is a member's balance against the group — that is what the
/// balance card and the transfers are derived from, so it is what tapping them must explain.
struct BalanceAuditSheet: View {
    let ledger: LedgerStore
    let userId: UserID
    let groupId: GroupID
    let memberId: MemberID

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
        let entries = group.breakdown(for: memberId)
        let isMe = memberId == group.me(for: userId)?.id
        let memberName = isMe
            ? String(localized: "Du")
            : group.members[memberId]?.displayName ?? "?"

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(isMe ? String(localized: "Din balans") : memberName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 20)

                if entries.isEmpty {
                    Text("Inga utgifter eller betalningar än.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity)
                        .cardSurface()
                } else {
                    entriesCard(entries, group: group, isMe: isMe, memberName: memberName)
                    Text("Varje siffra kan spåras till sina utgifter.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 26)
        }
        .background(AmbientBackground())
    }

    private func entriesCard(
        _ entries: [LedgerEntry], group: GroupState, isMe: Bool, memberName: String
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                if index > 0 {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
                AuditRow(entry: entry, group: group)
            }
            TotalRow(
                // The API's guarantee, restated where it is visible: the last running total IS
                // the balance. Render that value rather than recomputing anything.
                totalMinor: entries.last?.runningTotalMinor ?? 0,
                currency: group.currency,
                isMe: isMe,
                memberName: memberName
            )
        }
        .cardSurface(padding: 14)
    }
}

// MARK: - Rows

private struct AuditRow: View {
    let entry: LedgerEntry
    let group: GroupState

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(emoji) \(label)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                Text("löpande: \(MoneyFormat.string(entry.runningTotalMinor, group.currency, sign: .always))")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .monospacedDigit()
            }
            Spacer()
            SignedAmountText(
                amountMinor: entry.deltaMinor,
                currency: group.currency,
                size: 15,
                accessibilityPhrase: "\(label), \(MoneyFormat.string(entry.deltaMinor, group.currency, sign: .always))"
            )
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    /// Expenses carry their category's emoji; payments read as a settle-up.
    private var emoji: String {
        switch entry.source {
        case .expense(let id):
            return Categories.emoji(for: group.expenses[id]?.categoryId ?? "")
        case .payment:
            return "🤝"
        }
    }

    /// A payment with no note has no title of its own — Core deliberately does not invent one,
    /// because the only thing it could reach for is the raw wire value of `method`. The label
    /// belongs here, where it can be localised.
    private var label: String {
        if !entry.title.isEmpty { return entry.title }

        switch entry.source {
        case .payment:
            return String(localized: "Betalning", comment: "Audit row label for a settle-up with no note")
        case .expense:
            return String(localized: "Utgift", comment: "Audit row label for an expense with no description")
        }
    }
}

private struct TotalRow: View {
    let totalMinor: Int64
    let currency: CurrencyCode
    let isMe: Bool
    let memberName: String

    var body: some View {
        HStack {
            Text(phrase).font(.body.weight(.bold)).foregroundStyle(Theme.ink)
            Spacer()
            SignedAmountText(
                amountMinor: totalMinor,
                currency: currency,
                size: 17,
                accessibilityPhrase: "\(phrase): \(MoneyFormat.string(abs(totalMinor), currency))"
            )
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.ink).frame(height: 2)
        }
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
    }

    private var phrase: String {
        switch (isMe, totalMinor > 0, totalMinor < 0) {
        case (true, true, _): return String(localized: "Du ska få")
        case (true, _, true): return String(localized: "Du är skyldig")
        case (true, _, _): return String(localized: "Ni är kvitt")
        case (false, true, _): return String(localized: "\(memberName) ska få")
        case (false, _, true): return String(localized: "\(memberName) är skyldig")
        case (false, _, _): return String(localized: "\(memberName) är kvitt")
        }
    }
}
