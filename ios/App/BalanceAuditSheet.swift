import SwiftUI
import KvittaCore
import KvittaStorage

/// Balansgranskning — the trust view. Every expense and payment behind one member's balance,
/// oldest first, with a running total whose last line is exactly the number that was tapped.
/// This is what makes a balance auditable rather than a number you have to trust.
///
/// All the arithmetic is `GroupState.breakdown(for:)`; this view only renders it — and, since the
/// design review, leads with `BalanceSummary`'s regrouping of the same entries: "din andel − det
/// du betalade = …" is the sentence people came for, the list is the proof. One deliberate
/// deviation from the mockup: the mockup sketches a pairwise "Din balans med Jonas", but the
/// audited quantity in this app is a member's balance against the group — that is what the
/// balance card and the transfers are derived from, so it is what tapping them must explain.
///
/// Steven ark (#149, README §2.5 `NavTitleBar`, §4.4 "Saldorevision… STÄLLNING → utfälld rad →
/// 'Så räknas det'"): only `ios/App/Steven/` tokens below, no `Theme`/`cardSurface` survivors.
struct BalanceAuditSheet: View {
    let ledger: LedgerStore
    let userId: UserID
    let groupId: GroupID
    let memberId: MemberID

    @Environment(\.dismiss) private var dismiss

    private var group: GroupState? { ledger.state[groupId] }

    var body: some View {
        if let group {
            content(for: group)
        } else {
            ContentUnavailableView("Gruppen finns inte längre", systemImage: "person.2.slash")
                .background(StevenColor.screen)
        }
    }

    private func content(for group: GroupState) -> some View {
        let isMe = memberId == group.me(for: userId)?.id
        let memberName = isMe
            ? String(localized: "Du")
            : group.members[memberId]?.displayName ?? "?"
        // One audit card per currency bucket the member has lines in. A running total across
        // SEK and DKK would be adding kronor to kroner, so the buckets never share a card.
        let perCurrency = group.balances().currencies
            .map { ($0, group.breakdown(for: memberId, in: $0)) }
            .filter { !$0.1.isEmpty }

        return VStack(spacing: 0) {
            Steven.NavTitleBar(leading: .close { dismiss() }) {
                Text(verbatim: isMe ? String(localized: "Din balans") : memberName)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if perCurrency.isEmpty {
                        Steven.Card {
                            Text("Inga utgifter eller betalningar än.")
                                .stevenFont(.rowTitle)
                                .foregroundStyle(StevenColor.muted)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        ForEach(perCurrency, id: \.0) { currency, entries in
                            if perCurrency.count > 1 {
                                Steven.SectionHeader(verbatim: currency.code)
                            }
                            // The answer first: share − paid = result. Then the receipts.
                            if let summary = BalanceSummary(group: group, memberId: memberId, currency: currency) {
                                SummaryCard(summary: summary, explicit: currency != group.currency,
                                            isMe: isMe, memberName: memberName)
                            }
                            Steven.SectionHeader("Så här räknade vi")
                            entriesCard(entries, group: group, currency: currency,
                                        isMe: isMe, memberName: memberName)
                        }
                    }
                }
                .padding(.horizontal, StevenMetric.gutter)
                .padding(.top, 8)
                .padding(.bottom, 26)
            }
        }
        .background(StevenColor.screen)
    }

    private func entriesCard(
        _ entries: [LedgerEntry], group: GroupState, currency: CurrencyCode,
        isMe: Bool, memberName: String
    ) -> some View {
        Steven.Card(padding: 14) {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    if index > 0 {
                        Steven.Hairline()
                    }
                    AuditRow(entry: entry, group: group, currency: currency)
                }
                TotalRow(
                    // The API's guarantee, restated where it is visible: the last running total IS
                    // the balance. Render that value rather than recomputing anything.
                    totalMinor: entries.last?.runningTotalMinor ?? 0,
                    currency: currency,
                    explicit: currency != group.currency,
                    isMe: isMe,
                    memberName: memberName
                )
            }
        }
    }
}

// MARK: - Summary

/// The calculation as a person would say it, one line per side, tabular digits so the column
/// scans. Settle-ups get their own lines rather than hiding inside "paid": a payment you sent is
/// money that moved, and naming it is what lets someone check it against their Swish history.
private struct SummaryCard: View {
    let summary: BalanceSummary
    let explicit: Bool
    let isMe: Bool
    let memberName: String

    var body: some View {
        Steven.Card(padding: 14) {
            VStack(spacing: 0) {
                line(
                    isMe ? String(localized: "Din andel av utgifterna") : String(localized: "Andel av utgifterna"),
                    amountMinor: summary.shareMinor
                )
                if summary.receivedMinor > 0 {
                    line(
                        isMe ? String(localized: "Betalningar du fått") : String(localized: "Betalningar mottagna"),
                        amountMinor: summary.receivedMinor
                    )
                }
                line(
                    isMe ? String(localized: "Det du betalade") : String(localized: "Betalade"),
                    amountMinor: -summary.paidMinor
                )
                if summary.sentMinor > 0 {
                    line(
                        isMe ? String(localized: "Betalningar du skickat") : String(localized: "Betalningar skickade"),
                        amountMinor: -summary.sentMinor
                    )
                }
                TotalRow(
                    // Sign flipped on purpose: the lines above read as "what you owe", so a positive
                    // running result is a debt in that column. The phrase and colour still follow
                    // the balance's own convention, which is what the hero card shows.
                    totalMinor: summary.resultMinor,
                    currency: summary.currency,
                    explicit: explicit,
                    isMe: isMe,
                    memberName: memberName
                )
            }
        }
    }

    private func line(_ label: String, amountMinor: Int64) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .stevenFont(.rowTitle)
                .foregroundStyle(StevenColor.ink)
            Spacer()
            // Zero has no sign to show; a negative line reads "−900 kr" so the subtraction is
            // visible on the page rather than implied by the label.
            Steven.MoneyText(
                amountMinor: amountMinor,
                currency: summary.currency,
                font: .rowTitle,
                tone: .ink,
                sign: amountMinor < 0 ? .always : .none,
                explicit: explicit
            )
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Rows

private struct AuditRow: View {
    let entry: LedgerEntry
    let group: GroupState
    let currency: CurrencyCode

    /// The kr-collision rule: entries in a non-primary bucket spell out their code, so a DKK
    /// line never reads as "kr" just because both currencies happen to say it.
    private var explicit: Bool { currency != group.currency }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .stevenFont(.rowTitle)
                    .foregroundStyle(StevenColor.ink)
                Text(verbatim: "löpande: \(StevenMoneyFormat.string(entry.runningTotalMinor, currency, sign: .always, explicit: explicit))")
                    .stevenFont(.footnote)
                    .foregroundStyle(StevenColor.muted)
                    .monospacedDigit()
            }
            Spacer()
            Steven.MoneyText(
                amountMinor: entry.deltaMinor,
                currency: currency,
                font: .rowTitle,
                tone: .direction,
                explicit: explicit
            )
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
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
    var explicit: Bool = false
    let isMe: Bool
    let memberName: String

    var body: some View {
        HStack {
            Text(phrase).stevenFont(.rowTitleBold).foregroundStyle(StevenColor.ink)
            Spacer()
            Steven.MoneyText(
                amountMinor: totalMinor,
                currency: currency,
                font: .rowTitleBold,
                tone: .direction,
                explicit: explicit
            )
        }
        .padding(.top, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(StevenColor.ink).frame(height: 2)
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
