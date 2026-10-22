import SwiftUI
import UIKit
import KvittaCore
import KvittaStorage

/// Gruppvy (README §1.2, §6.2, §6.4): Steven's shell — nav row, head, three tabs, fixed balance
/// footer — around UTGIFTER. STÄLLNING and BETALNINGAR keep today's content unchanged until
/// Steven 5 and 6 (#149, #150) rebuild them.
///
/// Everything here is a read of the projection — `balances()`, `suggestedTransfers()`,
/// `visibleExpenses` — plus two writes: "Betala" opens `SettleUpSheet`, which records a
/// `PaymentRecorded`; the payee's pending-payment answer records `PaymentConfirmed`/`PaymentDisputed`.
struct GroupDetailView: View {
    let ledger: LedgerStore
    let userId: UserID
    let groupId: GroupID
    var payees = PayeeDirectory()
    let invites: InviteModel
    let profile: UserProfile
    let photos: GroupPhotoSyncer
    let rates: RateStore
    let profiles: ProfileSyncer
    var displayModes = CurrencyDisplayStore()

    @Environment(\.dismiss) private var dismiss

    @State private var settlingTransfer: TransferPresentation?
    @State private var auditingMember: MemberID?
    @State private var viewingExpense: ExpenseID?
    @State private var showingDeleted = false
    @State private var restoreFailure: String?
    @State private var confirmFailure: String?
    @State private var showingMembers = false
    @State private var showingPhoto = false
    /// The Påminn share sheet's text, set once there is something to share.
    @State private var remindingText: String?
    /// Adding an expense from inside the group it belongs to — the group is the screen you are
    /// standing on, so there is nothing to guess.
    @State private var expenseModel: NewExpenseModel?
    /// Which of the three tabs is up. Per visit: a group opens on its expenses.
    @State private var tab: GroupTab = .expenses
    /// The live group out of the projection. `nil` only if the group vanished mid-navigation,
    /// which a rebuild from a bad log could theoretically produce — show nothing rather than crash.
    private var group: GroupState? { ledger.state[groupId] }

    var body: some View {
        if let group {
            content(for: group)
                // Co-members' Swish numbers from their own profiles, into the same directory the
                // settle-up sheet reads — so the number is usually just there, and the ask-for-it
                // alert is the offline-or-unlinked fallback. The group photo rides the same
                // moment: opening a group is when its shared picture comes down (or a pending
                // local pick goes up).
                .task {
                    async let payeeRefresh: Void = profiles.refreshPayees(in: groupId, into: payees)
                    async let photoRefresh: Void = photos.refresh(groupId)
                    _ = await (payeeRefresh, photoRefresh)
                }
        } else {
            ContentUnavailableView("Gruppen finns inte längre", systemImage: "person.2.slash")
                .background(AmbientBackground())
        }
    }

    private func content(for group: GroupState) -> some View {
        let meId = group.me(for: userId)?.id
        let canSplit = group.activeMembers.count >= 2
        let mode = displayModes.mode(for: groupId)
        // One fold per render. Every card below reads from this value instead of asking the
        // projection again.
        let balances = group.balances()
        let transfers = balances.suggestedTransfers
        let total = totalSpent(group)
        let footerBalances: [Steven.Balance] = group.nets(for: userId, in: balances)
            .map { Steven.Balance(netMinor: $0.amountMinor, currency: $0.currency) }
            .filter { $0 != .settled }

        return VStack(spacing: 0) {
            GroupNavBar(group: group, onBack: { dismiss() }, onMembers: { showingMembers = true })
            ScrollView {
                VStack(spacing: 0) {
                    GroupHeader(
                        group: group, meId: meId, totalMinor: total.amountMinor, totalApproximate: total.approximate,
                        photo: photos.images.uiImage(for: groupId), onShowPhoto: { showingPhoto = true }
                    )
                    Steven.UnderlineTabs(selection: $tab, tabs: [
                        (GroupTab.expenses, "Utgifter"), (.standing, "Ställning"), (.payments, "Betalningar"),
                    ])
                    tabContent(group: group, meId: meId, canSplit: canSplit, mode: mode,
                              balances: balances, transfers: transfers)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(StevenColor.content)
                }
            }
            .background(StevenColor.surface)
        }
        .background(StevenColor.screen)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            Steven.BalanceFooter(
                balances: footerBalances,
                onPay: {
                    if let transfer = payTransfer(group, meId, balances, transfers) {
                        settlingTransfer = TransferPresentation(transfer: transfer)
                    }
                },
                onRemind: {
                    if let transfer = remindTransfer(group, meId, balances, transfers) {
                        remindingText = reminderText(for: transfer, in: group)
                    }
                },
                onAdd: { expenseModel = NewExpenseModel(ledger: ledger, userId: userId, groupId: groupId) }
            )
        }
        .sheet(isPresented: $showingMembers) {
            MembersSheet(ledger: ledger, userId: userId, groupId: groupId, invites: invites, profile: profile)
        }
        .sheet(item: $settlingTransfer) { presentation in
            SettleUpSheet(ledger: ledger, userId: userId, groupId: groupId,
                          transfer: presentation.transfer, payees: payees)
                .presentationDetents([.large])
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
        .sheet(isPresented: $showingPhoto) {
            GroupPhotoViewer(groupName: group.name, groupId: groupId, photos: photos)
        }
        .sheet(isPresented: Binding(
            get: { remindingText != nil },
            set: { shown in if !shown { remindingText = nil } }
        )) {
            ShareSheet(items: [remindingText ?? ""])
        }
    }

    @ViewBuilder
    private func tabContent(
        group: GroupState, meId: MemberID?, canSplit: Bool, mode: CurrencyDisplay,
        balances: GroupBalances, transfers: [SuggestedTransfer]
    ) -> some View {
        switch tab {
        case .expenses:
            GroupExpensesTab(
                group: group, meId: meId, mode: mode, canSplit: canSplit,
                onSelect: { viewingExpense = $0 },
                onInvite: { showingMembers = true },
                onAddExpense: { expenseModel = NewExpenseModel(ledger: ledger, userId: userId, groupId: groupId) },
                showingDeleted: $showingDeleted, restoreFailure: restoreFailure, onRestore: restore
            )
            .padding(.top, 8)
            .padding(.bottom, 24)

        case .standing, .payments:
            // Neither tab has its own Steven screen yet (those are #149 and #150) — both show
            // today's existing content in the meantime, per the issue that asked for this shell.
            legacyStandingContent(group: group, balances: balances, transfers: transfers, meId: meId, mode: mode)
        }
    }

    private func legacyStandingContent(
        group: GroupState, balances: GroupBalances, transfers: [SuggestedTransfer],
        meId: MemberID?, mode: CurrencyDisplay
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            PendingPaymentsCard(group: group, meId: meId, failure: confirmFailure, onAnswer: answer)
            if let about = group.about {
                Text(about).font(.subheadline).foregroundStyle(Theme.secondary).padding(.horizontal, 4)
            }
            TransfersCard(group: group, transfers: transfers, meId: meId, mode: mode,
                          onSettle: { settlingTransfer = TransferPresentation(transfer: $0) })
            MembersCard(group: group, balances: balances, meId: meId, mode: mode, rates: rates.rates,
                       myPhoto: profile.avatarData) { auditingMember = $0 }
            GroupRepaymentHistory(group: group)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    private func restore(_ expenseId: ExpenseID) {
        do {
            try ledger.record(.expenseRestored(EmptyPayload()), entityId: expenseId.rawValue, in: groupId)
            restoreFailure = nil
        } catch {
            restoreFailure = String(describing: error)
        }
    }

    /// The payee's answer to a pending payment (M8). Written like every other event; the
    /// projector only accepts it because this device's author *is* the payee — anyone else's
    /// confirmation is skipped as forged on every device that replays it.
    private func answer(_ payment: Payment, confirmed: Bool) {
        do {
            try ledger.record(
                confirmed ? .paymentConfirmed(EmptyPayload()) : .paymentDisputed(EmptyPayload()),
                entityId: payment.id.rawValue,
                in: groupId
            )
            confirmFailure = nil
        } catch {
            confirmFailure = String(describing: error)
        }
    }

    /// The group's total spend for `GroupHeader` (§1.2): every non-deleted expense, summed in the
    /// primary currency. A mixed group converts the rest with today's ECB rates and the result is
    /// marked ≈; with no rate cached yet it falls back to adding the raw minor units across
    /// currencies — wrong in principle, but already flagged ≈, and it only happens offline before
    /// any rate has ever been fetched.
    private func totalSpent(_ group: GroupState) -> (amountMinor: Int64, approximate: Bool) {
        var totalMinor: Int64 = 0
        for expense in group.visibleExpenses {
            if expense.currency == group.currency {
                totalMinor += expense.amountMinor
            } else if let converted = rates.rates?.convert(
                Money(amountMinor: expense.amountMinor, currency: expense.currency), to: group.currency
            ) {
                totalMinor += converted.amountMinor
            } else {
                totalMinor += expense.amountMinor
            }
        }
        let mixed = Set(group.visibleExpenses.map(\.currency)).count > 1
        return (totalMinor, mixed)
    }

    /// The suggested transfer "Betala" settles: the first currency where you owe (6.4 — "knappen
    /// gäller den första öppna"), among the ones you are the payer of.
    private func payTransfer(
        _ group: GroupState, _ meId: MemberID?, _ balances: GroupBalances, _ transfers: [SuggestedTransfer]
    ) -> SuggestedTransfer? {
        guard let meId, let currency = firstOpenCurrency(group, balances) else { return nil }
        return transfers.first { $0.currency == currency && $0.from == meId }
    }

    /// The suggested transfer "Påminn" is about: the first currency where somebody owes you.
    private func remindTransfer(
        _ group: GroupState, _ meId: MemberID?, _ balances: GroupBalances, _ transfers: [SuggestedTransfer]
    ) -> SuggestedTransfer? {
        guard let meId, let currency = firstOpenCurrency(group, balances) else { return nil }
        return transfers.first { $0.currency == currency && $0.to == meId }
    }

    /// The currency of the first non-settled line in `GroupHeader`'s own order (primary first) —
    /// the one decision 6.4's "den första öppna" means.
    private func firstOpenCurrency(_ group: GroupState, _ balances: GroupBalances) -> CurrencyCode? {
        group.nets(for: userId, in: balances).first { $0.amountMinor != 0 }?.currency
    }

    /// "Påminn" (6.4): a ready-made share-sheet message with the amount, the group and — when the
    /// profile has one — your own payment number. The phone prints in international form
    /// (+46701234567) rather than Carl's pretty "070-123 45 67" example: there is no national
    /// formatter for it yet (flagged in the PR).
    private func reminderText(for transfer: SuggestedTransfer, in group: GroupState) -> String {
        let amount = StevenMoneyFormat.string(transfer.amountMinor, transfer.currency, explicit: false)
        let groupTitle = GroupBadge.title(of: group.name)
        guard let phone = profile.paymentPhone else {
            return String(localized: "Hej! Du är skyldig mig \(amount) i \(groupTitle). 🙂")
        }
        switch phone.country {
        case .sweden:
            return String(localized: "Hej! Du är skyldig mig \(amount) i \(groupTitle). Swisha gärna till \(phone.international) 🙂")
        case .denmark:
            return String(localized: "Hej! Du är skyldig mig \(amount) i \(groupTitle). Betala gärna med MobilePay till \(phone.international) 🙂")
        }
    }
}

/// The group's three tabs (§1.2). `standing`/`payments` render the same, old content for now —
/// see `GroupDetailView.legacyStandingContent`.
enum GroupTab: Hashable {
    case expenses, standing, payments
}

/// The system share sheet, presented imperatively from "Påminn" rather than a `ShareLink` (which
/// has to be the tapped control itself) — `Steven.BalanceFooter`'s action is a plain closure.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Payments waiting on somebody's word (M8). The payee gets the two buttons; everyone else
/// sees whose word is being waited on, which is what makes the state legible instead of spooky.
private struct PendingPaymentsCard: View {
    let group: GroupState
    let meId: MemberID?
    let failure: String?
    let onAnswer: (Payment, Bool) -> Void

    var body: some View {
        let pending = group.paymentsAwaitingConfirmation()
        if !pending.isEmpty {
            SectionHeader(title: String(localized: "Väntar på bekräftelse"))
            VStack(spacing: 0) {
                ForEach(Array(pending.enumerated()), id: \.element.id) { index, payment in
                    if index > 0 {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                    row(for: payment)
                }
                if let failure {
                    Text(failure).font(.footnote).foregroundStyle(Theme.negative)
                        .padding(.top, 8)
                }
            }
            .cardSurface(padding: 14)
        }
    }

    private func row(for payment: Payment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("\(name(payment.fromMemberId)) → \(name(payment.toMemberId))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                NeutralAmountText(
                    amountMinor: payment.amountMinor,
                    currency: payment.currency,
                    size: 15,
                    explicit: payment.currency != group.currency
                )
                Spacer(minLength: 8)
            }

            if payment.toMemberId == meId {
                HStack(spacing: 10) {
                    Button(String(localized: "Ja, jag har fått pengarna")) {
                        onAnswer(payment, true)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.positive, in: .rect(cornerRadius: 18))
                    .buttonStyle(ScaleButtonStyle())

                    Button(String(localized: "Nej")) {
                        onAnswer(payment, false)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.negative)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.negative.opacity(0.12), in: .rect(cornerRadius: 18))
                    .buttonStyle(ScaleButtonStyle())
                }
            } else {
                Text("Väntar på \(name(payment.toMemberId))")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func name(_ memberId: MemberID) -> String {
        if memberId == meId { return String(localized: "Du") }
        return group.members[memberId]?.displayName ?? "?"
    }
}

/// `SuggestedTransfer` is a plain Core value; wrap it for `.sheet(item:)`.
private struct TransferPresentation: Identifiable {
    let id = UUID()
    let transfer: SuggestedTransfer
}

// MARK: - Vem är skyldig vem

private struct TransfersCard: View {
    let group: GroupState
    /// From the screen's one fold — see `GroupDetailView.content`.
    let transfers: [SuggestedTransfer]
    let meId: MemberID?
    let mode: CurrencyDisplay
    let onSettle: (SuggestedTransfer) -> Void

    /// Transfers are always native — a converted transfer would be an unpayable number at a
    /// rate somebody disputes. The filter narrows; converted mode leaves them exact.
    private var filteredTransfers: [SuggestedTransfer] {
        if case .only(let currency) = mode {
            return transfers.filter { $0.currency == currency }
        }
        return transfers
    }

    var body: some View {
        let transfers = filteredTransfers
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
                        onSettle: { onSettle(transfer) }
                    )
                }
            }
            .cardSurface(padding: 8)
        }
    }
}

private struct TransferRow: View {
    let group: GroupState
    let meId: MemberID?
    let transfer: SuggestedTransfer
    let onSettle: () -> Void

    @Environment(\.myAvatarPhoto) private var myPhoto

    var body: some View {
        // The whole row opens Gör upp — one target, a chevron, no pill per row. The audit
        // behind a transfer is one tap away on the member rows below.
        Button(action: onSettle) {
                HStack(spacing: 12) {
                    // The other person — the one the sentence is about from where you stand.
                    // Between two others, the one paying.
                    let counterparty = transfer.from == meId ? transfer.to : transfer.from
                    Avatar(name: name(counterparty), photo: counterparty == meId ? myPhoto : nil, size: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(name(transfer.from)) → \(name(transfer.to))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        SignedAmountText(
                            amountMinor: transfer.amountMinor,
                            currency: transfer.currency,
                            size: 17,
                            sign: .none,
                            explicit: transfer.currency != group.currency,
                            accessibilityPhrase: spokenPhrase
                        )
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(.rect)
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenPhrase)
    }

    private func name(_ memberId: MemberID) -> String {
        if memberId == meId { return String(localized: "Du") }
        return group.members[memberId]?.displayName ?? "?"
    }

    private var spokenPhrase: String {
        "\(name(transfer.from)) → \(name(transfer.to)), \(MoneyFormat.string(transfer.amountMinor, transfer.currency, explicit: true))"
    }
}

// MARK: - Medlemmar

/// Everyone in the group with where they stand, the mockup's member list. Tapping a row opens
/// the audit for that member — same trust rule as everywhere else.
private struct MembersCard: View {
    let group: GroupState
    /// From the screen's one fold. Reading `group.balances()` per row made a list of eight
    /// members re-fold the whole ledger eight times per frame.
    let balances: GroupBalances
    let meId: MemberID?
    let mode: CurrencyDisplay
    let rates: ExchangeRates?
    /// Your profile picture from Jag — the one picture you have, shown on your own row here the
    /// same as everywhere else. Other members render as initials until profile photos sync.
    let myPhoto: Data?
    let onAudit: (MemberID) -> Void

    var body: some View {
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
                        Avatar(
                            name: member.displayName,
                            photo: member.id == meId ? myPhoto : nil,
                            size: 36
                        )
                        Text(member.id == meId ? String(localized: "Du") : member.displayName)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            ForEach(lines(for: member.id), id: \.money.currency) { line in
                                HStack(spacing: 3) {
                                    if line.approximate {
                                        Text("≈").font(.caption).foregroundStyle(Theme.tertiary)
                                    }
                                    SignedAmountText(
                                        amountMinor: line.money.amountMinor,
                                        currency: line.money.currency,
                                        size: 15,
                                        explicit: line.money.currency != group.currency,
                                        accessibilityPhrase: "\(member.displayName): \(BalanceDirection(line.money.amountMinor).spokenWord) \(MoneyFormat.string(abs(line.money.amountMinor), line.money.currency, explicit: true))"
                                    )
                                }
                            }
                        }
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

    /// A member's balance lines under the current mode: every bucket, one bucket, or one ≈ sum.
    private func lines(for memberId: MemberID) -> [(money: Money, approximate: Bool)] {
        let buckets = balances.byCurrency
        switch mode {
        case .native:
            // Primary first, matching the hero.
            let all = buckets.map { $0.money(for: memberId) }
            return all.sorted { lhs, rhs in
                if lhs.currency == group.currency { return true }
                if rhs.currency == group.currency { return false }
                return lhs.currency.code < rhs.currency.code
            }.map { ($0, false) }
        case .only(let currency):
            return buckets.filter { $0.currency == currency }
                .map { ($0.money(for: memberId), false) }
        case .converted:
            guard let rates else { return lines(forNative: memberId) }
            var totalMinor: Int64 = 0
            var stubborn: [(Money, Bool)] = []
            var anyConverted = false
            for bucket in buckets {
                let money = bucket.money(for: memberId)
                if let converted = rates.convert(money, to: group.currency) {
                    totalMinor += converted.amountMinor
                    if money.currency != group.currency && money.amountMinor != 0 { anyConverted = true }
                } else {
                    stubborn.append((money, false))
                }
            }
            return [(Money(amountMinor: totalMinor, currency: group.currency), anyConverted)] + stubborn
        }
    }

    private func lines(forNative memberId: MemberID) -> [(money: Money, approximate: Bool)] {
        balances.byCurrency.map { ($0.money(for: memberId), false) }
    }
}

// MARK: - Shared

/// The small warm-grey section label. Takes a resolved string; localizable callers pass
/// `String(localized:)`, computed ones (month names) pass the value directly.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote)
            .textCase(.uppercase)
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
    }
}
