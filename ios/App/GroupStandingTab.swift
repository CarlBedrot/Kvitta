import SwiftUI
import KvittaCore

/// STÄLLNING: one Steven card per active member, lowest balance first, that unfolds into the
/// simplified transfers touching them (README §1.2, image 09).
///
/// **Not wired into `GroupDetailView` yet.** This tab lives behind Steven 4's (#148)
/// `UnderlineTabs` shell, which has not merged — `GroupDetailView` on `main` still uses the
/// pre-Steven `GroupSegment`/`GroupBottomBar` pair, so there is nowhere correct to mount this
/// view today. Once #148 lands, wire it in as the STÄLLNING case, passing it the same
/// `LedgerStore`-derived `group`/`balances` the UTGIFTER tab already folds once per render, and
/// `onSettle`/`onRemind` closures equivalent to `GroupDetailView`'s existing `SettleUpSheet` and
/// share-sheet handlers. Same pattern as `ReminderMessage` in #166: a new, correct, unwired file
/// rather than a guess at a shell that does not exist on `main` yet.
struct GroupStandingTab: View {
    let group: GroupState
    /// Folded once by the screen that hosts this tab — see `GroupDetailView.content`'s own rule.
    let balances: GroupBalances
    let meId: MemberID?
    let onSettle: (SuggestedTransfer) -> Void
    let onRemind: (SuggestedTransfer) -> Void
    let onAudit: (MemberID) -> Void

    var body: some View {
        let transfers = balances.suggestedTransfers
        let pendingPayments = group.paymentsAwaitingConfirmation()
        LazyVStack(spacing: StevenMetric.cardGap) {
            ForEach(sortedMembers) { member in
                MemberStandingCard(
                    group: group,
                    member: member,
                    meId: meId,
                    lines: balanceLines(for: member.id),
                    transfers: transfers.filter { $0.from == member.id || $0.to == member.id },
                    pending: pendingPayments.filter { $0.fromMemberId == member.id || $0.toMemberId == member.id },
                    onSettle: onSettle,
                    onRemind: onRemind,
                    onAudit: { onAudit(member.id) }
                )
            }
        }
        .padding(.horizontal, StevenMetric.gutter)
    }

    /// "Sorterat med minst saldo först" (09) — against the group's primary currency, the one
    /// bucket every member always has a position in.
    private var sortedMembers: [Member] {
        let primary = balances.balances(in: group.currency)
        return group.activeMembers.sorted { left, right in
            let leftAmount = primary?.amountMinor(for: left.id) ?? 0
            let rightAmount = primary?.amountMinor(for: right.id) ?? 0
            if leftAmount != rightAmount { return leftAmount < rightAmount }
            return left.displayName.localizedStandardCompare(right.displayName) == .orderedAscending
        }
    }

    /// "Flera valutor: en saldorad per valuta i kortet" — primary bucket first, same order
    /// `MembersCard.lines(for:)` already uses elsewhere on this screen.
    private func balanceLines(for memberId: MemberID) -> [(currency: CurrencyCode, amountMinor: Int64)] {
        balances.byCurrency
            .map { (currency: $0.currency, amountMinor: $0.amountMinor(for: memberId)) }
            .sorted { lhs, rhs in
                if lhs.currency == group.currency { return true }
                if rhs.currency == group.currency { return false }
                return lhs.currency.code < rhs.currency.code
            }
    }
}

// MARK: - Member card

private struct MemberStandingCard: View {
    let group: GroupState
    let member: Member
    let meId: MemberID?
    let lines: [(currency: CurrencyCode, amountMinor: Int64)]
    /// Simplified pairwise transfers touching this member, from the screen's one fold.
    let transfers: [SuggestedTransfer]
    /// Payments waiting on their payee (M8) that touch this member — shown as a flag, not acted
    /// on here; confirming or disputing stays on BETALNINGAR (#150).
    let pending: [Payment]
    let onSettle: (SuggestedTransfer) -> Void
    let onRemind: (SuggestedTransfer) -> Void
    let onAudit: () -> Void

    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isMe: Bool { member.id == meId }

    var body: some View {
        Steven.Card(padding: 0) {
            VStack(spacing: 0) {
                header
                if expanded {
                    Steven.Hairline()
                    disclosure
                }
            }
        }
    }

    private var header: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { expanded.toggle() }
        } label: {
            HStack(spacing: 14) {
                Steven.AvatarView(member: member, size: StevenMetric.avatarRow, isMe: isMe)
                Text(verbatim: isMe ? String(localized: "Du") : shortMemberName(member.displayName))
                    .stevenFont(.rowTitleBold)
                    .foregroundStyle(StevenColor.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    ForEach(lines, id: \.currency) { line in
                        balanceText(line)
                    }
                }
                Rectangle().fill(StevenColor.hairline).frame(width: 1, height: 28)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StevenColor.muted)
            }
            .padding(.horizontal, StevenMetric.gutter)
            .frame(minHeight: StevenMetric.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: accessibilityLabel))
    }

    @ViewBuilder
    private func balanceText(_ line: (currency: CurrencyCode, amountMinor: Int64)) -> some View {
        if line.amountMinor == 0 {
            Text("Kvitt").stevenFont(.rowTitle).foregroundStyle(StevenColor.muted)
        } else {
            Steven.MoneyText(
                amountMinor: line.amountMinor,
                currency: line.currency,
                font: .rowTitleBold,
                tone: .direction,
                explicit: line.currency != group.currency
            )
        }
    }

    @ViewBuilder
    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(transfers.enumerated()), id: \.offset) { index, transfer in
                if index > 0 { Steven.Hairline().padding(.horizontal, StevenMetric.gutter) }
                TransferDisclosureRow(
                    group: group, meId: meId, transfer: transfer,
                    onSettle: { onSettle(transfer) }, onRemind: { onRemind(transfer) }
                )
            }
            ForEach(Array(pending.enumerated()), id: \.offset) { index, payment in
                if index > 0 || !transfers.isEmpty {
                    Steven.Hairline().padding(.horizontal, StevenMetric.gutter)
                }
                PendingDisclosureRow(group: group, meId: meId, payment: payment)
            }
            Button(action: onAudit) {
                Text("Så räknas det")
                    .stevenFont(.footnoteBold)
                    .foregroundStyle(StevenColor.accent)
                    .frame(minHeight: StevenMetric.minimumHitTarget, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, StevenMetric.gutter)
        }
        .padding(.bottom, 4)
    }

    /// One phrase per currency line, reusing the exact catalog keys `BalanceAuditSheet.TotalRow`
    /// already draws from — so "whose balance is this" never depends on a colour alone (#139).
    private var accessibilityLabel: String {
        let name = isMe ? String(localized: "Du") : member.displayName
        return lines.map { line in
            let direction = directionPhrase(line.amountMinor, name: name)
            guard line.amountMinor != 0 else { return direction }
            return "\(direction) \(MoneyFormat.string(abs(line.amountMinor), line.currency, explicit: line.currency != group.currency))"
        }.joined(separator: ", ")
    }

    private func directionPhrase(_ amountMinor: Int64, name: String) -> String {
        switch (isMe, amountMinor > 0, amountMinor < 0) {
        case (true, true, _): return String(localized: "Du ska få")
        case (true, _, true): return String(localized: "Du är skyldig")
        case (true, _, _): return String(localized: "Ni är kvitt")
        case (false, true, _): return String(localized: "\(name) ska få")
        case (false, _, true): return String(localized: "\(name) är skyldig")
        case (false, _, _): return String(localized: "\(name) är kvitt")
        }
    }
}

// MARK: - Disclosure rows

/// "Ellen → Carl 676,55 kr" with **Betala** if you are the payer, **Påminn** if you are the
/// payee, and nothing between two other members — same actions as the Steven 4 footer (§6.4).
private struct TransferDisclosureRow: View {
    let group: GroupState
    let meId: MemberID?
    let transfer: SuggestedTransfer
    let onSettle: () -> Void
    let onRemind: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(name(transfer.from)) → \(name(transfer.to))")
                    .stevenFont(.rowTitle)
                    .foregroundStyle(StevenColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Steven.MoneyText(
                    amountMinor: transfer.amountMinor,
                    currency: transfer.currency,
                    font: .footnoteBold,
                    explicit: transfer.currency != group.currency
                )
            }
            Spacer(minLength: 8)
            actionButton
        }
        .padding(.horizontal, StevenMetric.gutter)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var actionButton: some View {
        if transfer.from == meId {
            Button("Betala", action: onSettle)
                .buttonStyle(Steven.FilledButtonStyle(height: StevenMetric.compactButtonHeight))
                .frame(width: 100)
        } else if transfer.to == meId {
            Button("Påminn", action: onRemind)
                .buttonStyle(Steven.OutlineButtonStyle(height: StevenMetric.compactButtonHeight))
                .frame(width: 100)
        }
    }

    private func name(_ memberId: MemberID) -> String {
        if memberId == meId { return String(localized: "Du") }
        return group.members[memberId]?.displayName ?? "?"
    }
}

/// "Väntar på bekräftelse" (M8): a payment already recorded, just not yet confirmed. Informational
/// only — the Ja/Nej decision stays on BETALNINGAR (#150), not here.
private struct PendingDisclosureRow: View {
    let group: GroupState
    let meId: MemberID?
    let payment: Payment

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(name(payment.fromMemberId)) → \(name(payment.toMemberId))")
                    .stevenFont(.rowTitle)
                    .foregroundStyle(StevenColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text("Väntar på bekräftelse")
                    .stevenFont(.footnote)
                    .foregroundStyle(StevenColor.muted)
            }
            Spacer(minLength: 8)
            Steven.MoneyText(
                amountMinor: payment.amountMinor,
                currency: payment.currency,
                font: .footnoteBold,
                tone: .muted,
                explicit: payment.currency != group.currency
            )
        }
        .padding(.horizontal, StevenMetric.gutter)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func name(_ memberId: MemberID) -> String {
        if memberId == meId { return String(localized: "Du") }
        return group.members[memberId]?.displayName ?? "?"
    }
}

/// "Ellen Ekwall" → "Ellen E" (README §1.2: first name plus the initial of the last). A one-word
/// name is left exactly as it is — there is nothing to shorten.
func shortMemberName(_ displayName: String) -> String {
    let parts = displayName.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard parts.count == 2, let initial = parts[1].first else { return displayName }
    return "\(parts[0]) \(initial)"
}
