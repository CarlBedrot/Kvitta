import SwiftUI
import PhotosUI
import KvittaCore
import KvittaStorage

/// Gruppvy: the hero balance, who owes whom, the members, and the expense list by month.
///
/// Everything here is a read of the projection — `balances()`, `suggestedTransfers()`,
/// `visibleExpenses` — plus one write path: a transfer's "Gör upp" opens `SettleUpSheet`, which
/// records a `PaymentRecorded` through `LedgerStore.record`.
struct GroupDetailView: View {
    let ledger: LedgerStore
    let userId: UserID
    let groupId: GroupID
    var payees = PayeeDirectory()
    let invites: InviteModel
    let profile: UserProfile
    let images: GroupImageStore
    let rates: RateStore
    let profiles: ProfileSyncer
    var displayModes = CurrencyDisplayStore()

    @State private var settlingTransfer: TransferPresentation?
    @State private var auditingMember: MemberID?
    @State private var viewingExpense: ExpenseID?
    @State private var showingDeleted = false
    @State private var restoreFailure: String?
    @State private var confirmFailure: String?
    @State private var showingMembers = false
    /// Adding an expense from inside the group it belongs to — the group is the screen you are
    /// standing on, so there is nothing to guess.
    @State private var expenseModel: NewExpenseModel?

    /// The live group out of the projection. `nil` only if the group vanished mid-navigation,
    /// which a rebuild from a bad log could theoretically produce — show nothing rather than crash.
    private var group: GroupState? { ledger.state[groupId] }

    var body: some View {
        if let group {
            content(for: group)
                // Co-members' Swish numbers from their own profiles, into the same directory the
                // settle-up sheet reads — so the number is usually just there, and the ask-for-it
                // alert is the offline-or-unlinked fallback.
                .task { await profiles.refreshPayees(in: groupId, into: payees) }
        } else {
            ContentUnavailableView("Gruppen finns inte längre", systemImage: "person.2.slash")
                .background(AmbientBackground())
        }
    }

    private func content(for group: GroupState) -> some View {
        let meId = group.me(for: userId)?.id
        let canSplit = group.activeMembers.count >= 2
        let mode = displayModes.mode(for: groupId)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // The trust rule (product principles): every balance on screen opens the exact
                // lines behind it. The card audits you; a member row audits that member.
                GroupHeroCard(
                    group: group,
                    userId: userId,
                    mode: mode,
                    rates: rates.rates,
                    photo: images.image(for: groupId),
                    onPhotoPicked: { images.set($0, for: groupId) },
                    onMode: { displayModes.set($0, for: groupId) },
                    onAudit: { if let meId { auditingMember = meId } }
                )

                if !canSplit {
                    SoloGroupCard { showingMembers = true }
                }

                // The "om gruppen" blurb, when someone has written one. Quiet text, not a card:
                // it is context, not data.
                if let about = group.about {
                    Text(about)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 4)
                }

                // A question outranks the shortcuts: somebody's books are waiting on the answer.
                PendingPaymentsCard(
                    group: group,
                    meId: meId,
                    failure: confirmFailure,
                    onAnswer: answer
                )

                if canSplit {
                    QuickActionsCard(
                        onAddExpense: {
                            expenseModel = NewExpenseModel(ledger: ledger, userId: userId, groupId: groupId)
                        },
                        onSettle: settleQuickAction(for: group, meId: meId),
                        onMembers: { showingMembers = true }
                    )
                }

                TransfersCard(
                    group: group,
                    meId: meId,
                    mode: mode,
                    onSettle: { settlingTransfer = TransferPresentation(transfer: $0) },
                    onAudit: { auditingMember = $0 }
                )

                MembersCard(group: group, meId: meId, mode: mode, rates: rates.rates,
                            myPhoto: profile.avatarData) {
                    auditingMember = $0
                }

                ExpenseList(group: group, meId: meId, mode: mode) { viewingExpense = $0 }
                DeletedExpensesSection(
                    group: group,
                    showingDeleted: $showingDeleted,
                    failure: restoreFailure,
                    onRestore: restore
                )
                Color.clear.frame(height: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .background(AmbientBackground())
        // The same + as on Grupper, but here the group is the screen you stand on, so it goes
        // straight to Ny utgift — no menu, no chooser. Hidden while you are alone in the group;
        // SoloGroupCard is already pointing at the way forward.
        .overlay(alignment: .bottomTrailing) {
            if canSplit {
                FAB {
                    expenseModel = NewExpenseModel(ledger: ledger, userId: userId, groupId: groupId)
                }
                .accessibilityLabel("Lägg till utgift")
                .padding(.trailing, 20)
                .padding(.bottom, 80)
            }
        }
        .navigationTitle(GroupBadge.title(of: group.name))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // The audit trail that leaves the app (product principles: CSV export early).
                // Generated lazily — the file only exists once somebody picks a destination.
                ShareLink(
                    item: CSVExportFile(group: group),
                    preview: SharePreview(CSVExportFile.filename(for: group))
                ) {
                    Label("Exportera CSV", systemImage: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingMembers = true
                } label: {
                    Label("Medlemmar", systemImage: "person.2")
                }
            }
        }
        .sheet(isPresented: $showingMembers) {
            MembersSheet(ledger: ledger, userId: userId, groupId: groupId, invites: invites,
                         profile: profile)
        }
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $settlingTransfer) { presentation in
            SettleUpSheet(ledger: ledger, userId: userId, groupId: groupId,
                          transfer: presentation.transfer, payees: payees, profile: profile)
                .presentationDetents([.medium])
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
    }

    /// The mockup's "Registrera betalning" quick action, wired to the flow that already exists:
    /// it opens Gör upp for the first suggested transfer that involves you — the one you can
    /// actually act on — or the first transfer at all when you are not part of any. `nil` (no
    /// transfers) hides the row: a settled group has nothing to register.
    private func settleQuickAction(for group: GroupState, meId: MemberID?) -> (() -> Void)? {
        let transfers = group.suggestedTransfers()
        guard let transfer = transfers.first(where: { $0.from == meId || $0.to == meId }) ?? transfers.first
        else { return nil }
        return { settlingTransfer = TransferPresentation(transfer: transfer) }
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
                // Not yours to answer — but showing *whose* answer is missing is what keeps the
                // frozen balance from looking like a bug.
                Text("Räknas när \(name(payment.toMemberId)) bekräftar. Utan svar räknas den efter \(PaymentStatus.autoConfirmAfterDays) dagar.")
                    .font(.caption)
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

// MARK: - Hero

/// Your position in this group: the sentence, the number large, and how much of the group is
/// already settled. Settled gets the green celebration instead of a zero. The group's badge sits
/// top-trailing and is a photo picker — tap it to give the group a face; the numbers themselves
/// still open the audit.
private struct GroupHeroCard: View {
    let group: GroupState
    let userId: UserID
    let mode: CurrencyDisplay
    let rates: ExchangeRates?
    let photo: Data?
    let onPhotoPicked: (Data?) -> Void
    let onMode: (CurrencyDisplay) -> Void
    let onAudit: () -> Void

    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        let isSettled = group.balances().isSettled
        VStack(spacing: 0) {
            // The photo as the card's crown — tapping it swaps it. The small badge below stays
            // the picker for a group that has no picture yet.
            if let photo {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    GroupPhotoBanner(photo: photo, height: 120)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Byt gruppbild")
            }
            Group {
                if isSettled {
                    settled
                } else {
                    open
                }
            }
            .padding(24)
        }
        .flushCardSurface(fill: isSettled ? Theme.positiveWash : Theme.card)
        .task(id: photoItem) { await loadPhoto() }
    }

    private var badge: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            GroupBadge(name: group.name, size: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Välj gruppbild")
    }

    private func loadPhoto() async {
        guard let photoItem else { return }
        // Downscaled before storing — UserDefaults is read back on every launch and a
        // camera-size image there would be megabytes. 800 because the photo is a full-width
        // banner now, not the 48-point circle the first version stored 256 for.
        if let data = try? await photoItem.loadTransferable(type: Data.self),
           let square = UIImage(data: data)?.squareThumbnail(side: 800),
           let jpeg = square.jpegData(compressionQuality: 0.8) {
            onPhotoPicked(jpeg)
        }
    }

    private var settled: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ni är kvitt 🎉")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Ingen i gruppen är skyldig någon något.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            if photo == nil {
                badge
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The nets to draw, shaped by the viewing mode. Exact by default; ≈ on request.
    private var displayedNets: [(money: Money, approximate: Bool)] {
        let nets = group.nets(for: userId)
        switch mode {
        case .native:
            return nets.map { ($0, false) }
        case .only(let currency):
            return nets.filter { $0.currency == currency }.map { ($0, false) }
        case .converted:
            guard let rates else { return nets.map { ($0, false) } }
            // Sum in the primary currency, integer math throughout. Any bucket the table
            // cannot convert keeps its own line rather than silently vanishing from the total.
            var totalMinor: Int64 = 0
            var stubborn: [(Money, Bool)] = []
            var anyConverted = false
            for net in nets {
                if let converted = rates.convert(net, to: group.currency) {
                    totalMinor += converted.amountMinor
                    if net.currency != group.currency { anyConverted = true }
                } else {
                    stubborn.append((net, false))
                }
            }
            return [(Money(amountMinor: totalMinor, currency: group.currency), anyConverted)] + stubborn
        }
    }

    private var open: some View {
        let nets = displayedNets
        let lead = nets.first
        let members = group.activeMembers.count
        // Settled here means settled in every bucket — one open DKK debt keeps you un-kvitt.
        let settledMembers = group.activeMembers.filter { member in
            group.balances().byCurrency.allSatisfy { $0.amountMinor(for: member.id) == 0 }
        }.count

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Button(action: onAudit) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let lead {
                            let direction = BalanceDirection(lead.money.amountMinor)
                            Text(direction == .owe ? "Du är skyldig" : (direction == .owed ? "Du ligger ute med" : "Din balans"))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.secondary)

                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                if lead.approximate {
                                    // The ≈ is the honesty marker: this number moves when the
                                    // ECB fixing does, without any money moving.
                                    Text("≈").font(.system(size: 28, weight: .medium))
                                        .foregroundStyle(Theme.tertiary)
                                }
                                SignedAmountText(
                                    amountMinor: lead.money.amountMinor,
                                    currency: lead.money.currency,
                                    size: 40,
                                    sign: .none,
                                    explicit: lead.money.currency != group.currency,
                                    accessibilityPhrase: "\(BalanceDirection(lead.money.amountMinor).spokenWord) \(MoneyFormat.string(abs(lead.money.amountMinor), lead.money.currency, explicit: true))"
                                )
                                .contentTransition(.numericText())
                            }

                            // The other buckets, exact and explicit — the default view leads with
                            // precision and never hides a currency you have money in.
                            ForEach(nets.dropFirst(), id: \.money.currency) { line in
                                SignedAmountText(
                                    amountMinor: line.money.amountMinor,
                                    currency: line.money.currency,
                                    size: 22,
                                    explicit: true
                                )
                            }
                        }

                        SettleProgressBar(
                            fraction: members == 0 ? 0 : Double(settledMembers) / Double(members),
                            tint: Theme.tint(forSign: lead?.money.amountMinor ?? 0)
                        )
                        .padding(.top, 8)

                        Text("\(settledMembers) av \(members) är kvitt")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(ScaleButtonStyle())

                VStack(alignment: .trailing, spacing: 10) {
                    // With a banner above, the badge would repeat the photo — the emoji identity
                    // is enough, and the banner itself is the picker.
                    if photo == nil {
                        badge
                    }
                    currencyMenu
                }
            }
        }
    }

    /// The mode switch, only shown once there is more than one currency to have an opinion about.
    @ViewBuilder
    private var currencyMenu: some View {
        let currencies = group.balances().currencies
        if currencies.count > 1 {
            Menu {
                Picker("Visa", selection: Binding(get: { mode }, set: onMode)) {
                    Text("Alla valutor").tag(CurrencyDisplay.native)
                    ForEach(currencies, id: \.self) { currency in
                        Text("Bara \(currency.code)").tag(CurrencyDisplay.only(currency))
                    }
                    if rates != nil {
                        Text("≈ i \(group.currency.code)").tag(CurrencyDisplay.converted)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "coloncurrencysign.arrow.circlepath")
                    Text(modeLabel)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.ink.opacity(0.05), in: .capsule)
            }
        }
    }

    private var modeLabel: String {
        switch mode {
        case .native: return String(localized: "Alla")
        case .only(let currency): return currency.code
        case .converted: return "≈ \(group.currency.code)"
        }
    }
}

// MARK: - A group of one

/// What a brand-new group shows instead of an expense button.
///
/// A group is created with only you in it now, so this is the state every group passes through.
/// It points at one place — Medlemmar — because that screen already holds both ways forward: the
/// invite link, and adding somebody by name for the friend who will never install anything.
private struct SoloGroupCard: View {
    let onOpenMembers: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bara du i gruppen än")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("Bjud in de andra med en länk, eller lägg till dem som namn om de inte tänker skaffa appen.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
            Button("Lägg till eller bjud in", action: onOpenMembers)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

// MARK: - Snabbfunktioner

/// The two things people come to a group screen to do, as named rows — the mockup's quick
/// actions. Settling is deliberately not here: a payment belongs to a specific transfer, and
/// those have their own "Gör upp" buttons just below.
private struct QuickActionsCard: View {
    let onAddExpense: () -> Void
    /// `nil` when the group is settled — there is no payment to register.
    let onSettle: (() -> Void)?
    let onMembers: () -> Void

    var body: some View {
        SectionHeader(title: String(localized: "Snabbfunktioner"))
        VStack(spacing: 0) {
            QuickActionRow(title: "Lägg till utgift", systemImage: "receipt", action: onAddExpense)
            if let onSettle {
                Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 64)
                QuickActionRow(title: "Registrera betalning", systemImage: "arrow.left.arrow.right", action: onSettle)
            }
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 64)
            QuickActionRow(title: "Medlemmar och inbjudan", systemImage: "person.badge.plus", action: onMembers)
        }
        .cardSurface(padding: 8)
    }
}

private struct QuickActionRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                IconBadge(systemImage: systemImage, size: 36)
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Vem är skyldig vem

private struct TransfersCard: View {
    let group: GroupState
    let meId: MemberID?
    let mode: CurrencyDisplay
    let onSettle: (SuggestedTransfer) -> Void
    let onAudit: (MemberID) -> Void

    /// Transfers are always native — a converted transfer would be an unpayable number at a
    /// rate somebody disputes. The filter narrows; converted mode leaves them exact.
    private var filteredTransfers: [SuggestedTransfer] {
        let all = group.suggestedTransfers()
        if case .only(let currency) = mode {
            return all.filter { $0.currency == currency }
        }
        return all
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
                        onSettle: { onSettle(transfer) },
                        onAudit: { onAudit(counterparty(of: transfer)) }
                    )
                }
            }
            .cardSurface(padding: 8)
        }
    }

    /// Who a tapped transfer should explain: the person on the other side of it from you —
    /// or the debtor when the transfer is between two others.
    private func counterparty(of transfer: SuggestedTransfer) -> MemberID {
        transfer.from == meId ? transfer.to : transfer.from
    }
}

private struct TransferRow: View {
    let group: GroupState
    let meId: MemberID?
    let transfer: SuggestedTransfer
    let onSettle: () -> Void
    let onAudit: () -> Void

    var body: some View {
        HStack {
            // The row body opens the audit; the trailing button settles. Two separate targets,
            // matching "tap any balance/transfer" from the design doc's trust rule.
            Button(action: onAudit) {
                HStack(spacing: 6) {
                    (Text(name(transfer.from)) + Text(verbatim: " → ") + Text(name(transfer.to)))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    SignedAmountText(
                        amountMinor: transfer.amountMinor,
                        currency: transfer.currency,
                        size: 15,
                        sign: .none,
                        explicit: transfer.currency != group.currency,
                        accessibilityPhrase: spokenPhrase
                    )
                    Spacer(minLength: 8)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Button("Gör upp", action: onSettle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.accent, in: .rect(cornerRadius: 18))
                .buttonStyle(ScaleButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        let buckets = group.balances().byCurrency
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
        group.balances().byCurrency.map { ($0.money(for: memberId), false) }
    }
}

// MARK: - Expense list

private struct ExpenseList: View {
    let group: GroupState
    let meId: MemberID?
    let mode: CurrencyDisplay
    let onSelect: (ExpenseID) -> Void

    /// The only-mode filter narrows the list; native and ≈ modes always show every expense
    /// in its own currency — an expense is a fact, and facts do not convert.
    private var visibleUnderMode: [Expense] {
        if case .only(let currency) = mode {
            return group.visibleExpenses.filter { $0.currency == currency }
        }
        return group.visibleExpenses
    }

    var body: some View {
        // visibleExpenses is already newest-first; chunk into months preserving that order.
        let months = MonthGroup.group(visibleUnderMode)
        ForEach(months) { month in
            SectionHeader(title: month.title)
            VStack(spacing: 0) {
                ForEach(Array(month.expenses.enumerated()), id: \.element.id) { index, expense in
                    if index > 0 {
                        Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 62)
                    }
                    Button {
                        onSelect(expense.id)
                    } label: {
                        ExpenseRow(group: group, meId: meId, expense: expense)
                            .contentShape(.rect)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .cardSurface(padding: 8)
        }
    }
}

/// The recovery half of soft delete. Hidden entirely until the group has deleted expenses;
/// restoring writes an `ExpenseRestored` and the row rejoins the list above.
private struct DeletedExpensesSection: View {
    let group: GroupState
    @Binding var showingDeleted: Bool
    let failure: String?
    let onRestore: (ExpenseID) -> Void

    var body: some View {
        let deleted = group.deletedExpenses
        if !deleted.isEmpty {
            Button {
                withAnimation(.spring(duration: 0.3)) { showingDeleted.toggle() }
            } label: {
                Text(showingDeleted ? "Dölj borttagna" : "Visa borttagna (\(deleted.count))")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 4)

            if showingDeleted {
                VStack(spacing: 0) {
                    ForEach(Array(deleted.enumerated()), id: \.element.id) { index, expense in
                        if index > 0 {
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                        }
                        HStack {
                            Text(expense.title)
                                .font(.subheadline)
                                .strikethrough()
                                .foregroundStyle(Theme.secondary)
                            Spacer()
                            NeutralAmountText(
                                amountMinor: expense.amountMinor,
                                currency: expense.currency,
                                size: 14
                            )
                            .foregroundStyle(Theme.secondary)
                            Button("Återställ") { onRestore(expense.id) }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                }
                .cardSurface(padding: 8)

                if let failure {
                    Text(failure).font(.footnote).foregroundStyle(Theme.negative)
                }
            }
        }
    }
}

/// One month's worth of expenses, newest month first.
private struct MonthGroup: Identifiable {
    let id: String
    let title: String
    let expenses: [Expense]

    static func group(_ expenses: [Expense]) -> [MonthGroup] {
        var order: [String] = []
        var byMonth: [String: [Expense]] = [:]
        for expense in expenses {
            let key = "\(expense.date.year)-\(expense.date.month)"
            if byMonth[key] == nil { order.append(key) }
            byMonth[key, default: []].append(expense)
        }
        return order.map { key in
            let first = byMonth[key]!.first!
            return MonthGroup(id: key, title: title(for: first.date), expenses: byMonth[key]!)
        }
    }

    /// "Juli" for the current year, "Juli 2025" for older ones. Locale-aware month names.
    private static func title(for date: CalendarDate) -> String {
        let symbols = Calendar.current.standaloneMonthSymbols
        let name = (1...12).contains(date.month) ? symbols[date.month - 1].capitalized : "?"
        let currentYear = CalendarDate(Date()).year
        return date.year == currentYear ? name : "\(name) \(date.year)"
    }
}

private struct ExpenseRow: View {
    let group: GroupState
    let meId: MemberID?
    let expense: Expense

    var body: some View {
        HStack(spacing: 14) {
            Text(Categories.emoji(for: expense.categoryId))
                .font(.system(size: 17))
                .frame(width: 36, height: 36)
                .background(Theme.accent.opacity(0.08), in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                Text(payerLine).font(.caption).foregroundStyle(Theme.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                NeutralAmountText(
                    amountMinor: expense.amountMinor,
                    currency: expense.currency,
                    size: 16,
                    explicit: expense.currency != group.currency
                )
                if let meId {
                    Text("din del \(MoneyFormat.string(expense.payload.share(of: meId), expense.currency, explicit: expense.currency != group.currency))")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var payerLine: String {
        let payers = expense.payload.payers
        guard let first = payers.first else { return "" }
        let name = first.memberId == meId
            ? String(localized: "Du")
            : group.members[first.memberId]?.displayName ?? "?"
        let paid = payers.count == 1
            ? String(localized: "\(name) betalade")
            : String(localized: "\(name) med flera betalade")
        // The day, so a row is placed in time without opening it. The month header carries the
        // month; this carries the date within it.
        return "\(paid) · \(expense.date.day)/\(expense.date.month)"
    }
}

// MARK: - Shared

/// The small warm-grey section label. Takes a resolved string; localizable callers pass
/// `String(localized:)`, computed ones (month names) pass the value directly.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .kerning(0.5)
            .foregroundStyle(Theme.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, 12)
    }
}
