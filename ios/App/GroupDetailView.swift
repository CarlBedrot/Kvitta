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
    let photos: GroupPhotoSyncer
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
    @State private var showingPhoto = false
    /// Adding an expense from inside the group it belongs to — the group is the screen you are
    /// standing on, so there is nothing to guess.
    @State private var expenseModel: NewExpenseModel?
    /// Which of the three views of the group is up. Per visit: a group opens on its expenses.
    @State private var segment: GroupSegment = .expenses
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
        // One fold per render. Every card below reads from this value — the hero, the
        // transfers, every member row — instead of asking the projection again.
        let balances = group.balances()
        let transfers = balances.suggestedTransfers
        // What was spent, and where the group stands — two screens behind one toggle at the
        // bottom, the way Steven does it, instead of one long scroll.
        return ScrollView {
            // Lazy: the expense months are built as they scroll in, not all on first paint.
            LazyVStack(alignment: .leading, spacing: 16) {
                switch segment {
                case .expenses:
                    if group.visibleExpenses.isEmpty {
                        EmptySegment(
                            text: canSplit ? "Inga utgifter än" : "Bjud in någon först",
                            button: canSplit ? nil : ("Bjud in", { showingMembers = true })
                        )
                    }
                    ExpenseList(group: group, expenses: group.visibleExpenses, meId: meId, mode: mode) { viewingExpense = $0 }
                    DeletedExpensesSection(
                        group: group,
                        showingDeleted: $showingDeleted,
                        failure: restoreFailure,
                        onRestore: restore
                    )

                case .standing:
                    // The trust rule (product principles): every balance on screen opens the
                    // exact lines behind it. The card audits you; a member row audits that member.
                    GroupHeroCard(
                        group: group,
                        balances: balances,
                        userId: userId,
                        mode: mode,
                        rates: rates.rates,
                        photo: photos.images.uiImage(for: groupId),
                        onPhotoPicked: { jpeg in Task { await photos.stage(jpeg, for: groupId) } },
                        onShowPhoto: { showingPhoto = true },
                        onMode: { displayModes.set($0, for: groupId) },
                        onAudit: { if let meId { auditingMember = meId } },
                        onAddExpense: {
                            expenseModel = NewExpenseModel(ledger: ledger, userId: userId, groupId: groupId)
                        },
                        onMembers: { showingMembers = true }
                    )

                    // Somebody's books are waiting on this answer, so it comes before anything
                    // historical.
                    PendingPaymentsCard(
                        group: group,
                        meId: meId,
                        failure: confirmFailure,
                        onAnswer: answer
                    )

                    // The "om gruppen" blurb, when someone has written one. Quiet text, not a
                    // card: it is context, not data.
                    if let about = group.about {
                        Text(about)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                            .padding(.horizontal, 4)
                    }

                    TransfersCard(
                        group: group,
                        transfers: transfers,
                        meId: meId,
                        mode: mode,
                        onSettle: { settlingTransfer = TransferPresentation(transfer: $0) }
                    )

                    MembersCard(group: group, balances: balances, meId: meId, mode: mode,
                                rates: rates.rates, myPhoto: profile.avatarData) {
                        auditingMember = $0
                    }

                }
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .background(GroupBackdrop(tint: Theme.GroupTint.forGroup(group.id),
                                  photo: photos.images.uiImage(for: groupId)))
        // The app's own tab bar steps aside inside a group; this bar takes its place — the
        // three views on the left, the one action on the right.
        .toolbarVisibility(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            GroupBottomBar(segment: $segment, canAdd: canSplit) {
                expenseModel = NewExpenseModel(ledger: ledger, userId: userId, groupId: groupId)
            }
        }
        .navigationTitle(GroupBadge.title(of: group.name))
        .toolbar {
            // One button up here, the way Swish does it: the things you do rarely live under it.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingMembers = true
                    } label: {
                        Label("Medlemmar och inbjudan", systemImage: "person.2")
                    }
                    // The audit trail that leaves the app (product principles: CSV export
                    // early). Generated lazily — the file only exists once somebody picks a
                    // destination.
                    ShareLink(
                        item: CSVExportFile(group: group),
                        preview: SharePreview(CSVExportFile.filename(for: group))
                    ) {
                        Label("Exportera CSV", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("Mer")
                }
            }
        }
        .sheet(isPresented: $showingMembers) {
            MembersSheet(ledger: ledger, userId: userId, groupId: groupId, invites: invites,
                         profile: profile)
        }
        // Inline, not large: the hero card now carries the full, wrapping name, and a large bar
        // title would show a truncated copy of it directly above the real thing.
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $settlingTransfer) { presentation in
            SettleUpSheet(ledger: ledger, userId: userId, groupId: groupId,
                          transfer: presentation.transfer, payees: payees)
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
        .sheet(isPresented: $showingPhoto) {
            GroupPhotoViewer(groupName: group.name, groupId: groupId, photos: photos)
        }
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

// MARK: - Hero

/// Your position in this group: the sentence, the number large, and how much of the group is
/// already settled. Settled gets the green celebration instead of a zero. The group's badge sits
/// top-trailing and is a photo picker — tap it to give the group a face; the numbers themselves
/// still open the audit.
private struct GroupHeroCard: View {
    let group: GroupState
    /// Folded once by the screen; every number on this card comes from here.
    let balances: GroupBalances
    let userId: UserID
    let mode: CurrencyDisplay
    let rates: ExchangeRates?
    let photo: UIImage?
    let onPhotoPicked: (Data?) -> Void
    /// Opens the full-image viewer — the banner is a crop, and the whole picture lives one tap in.
    let onShowPhoto: () -> Void
    let onMode: (CurrencyDisplay) -> Void
    let onAudit: () -> Void
    /// The two ways forward from a group with no expense yet — see `fresh`.
    let onAddExpense: () -> Void
    let onMembers: () -> Void

    @State private var photoItem: PhotosPickerItem?

    /// No expense yet. Every group starts here, and the balances are technically zero, but
    /// "Ni är kvitt 🎉" for a group nothing has happened in is a party for nothing — the
    /// celebration is saved for balances that were real and got cleared.
    private var isFresh: Bool { group.visibleExpenses.isEmpty }

    var body: some View {
        let isSettled = balances.isSettled
        VStack(spacing: 0) {
            // The photo as the card's crown — tapping it opens the whole image. The small badge
            // below stays the picker for a group that has no picture yet.
            if let photo {
                Button(action: onShowPhoto) {
                    // Adaptive height, but a strip either way: the widest a photo gets is a
                    // little taller than a 3:1 letterbox. The old range let a portrait picture
                    // claim half the screen and push the balance below the fold — the whole
                    // image is one tap away in the viewer, so the banner only has to say
                    // "this group", not show the picture.
                    GroupPhotoBanner(image: photo, aspect: 2.4...3.2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Visa gruppbilden")
            }
            // The name is the navigation title; the card is the answer to "what do I owe".
            Group {
                if isFresh {
                    fresh
                } else if isSettled {
                    settled
                } else {
                    open
                }
            }
            .padding(24)
        }
        .flushCardSurface()
        .task(id: photoItem) { await loadPhoto() }
    }

    private var badge: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                GroupBadge(name: group.name, size: 48, groupId: group.id)
                // The same camera chip as the profile avatar in Jag. The bare badge *was* the
                // picker before, and read as decoration — a function nobody can find does not
                // exist. Only shown while the group has no photo, so no clash with the badge's
                // own emoji corner.
                Image(systemName: "camera.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Theme.accent, in: .circle)
                    .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                    .offset(x: 4, y: 4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Välj gruppbild")
    }

    private func loadPhoto() async {
        guard let photoItem else { return }
        // Downscaled but *not* cropped — the viewer shows the whole picture, and a crop here
        // would be a crop nobody chose. The banner does its own cropping at draw time.
        if let data = try? await photoItem.loadTransferable(type: Data.self),
           let scaled = UIImage(data: data)?.downscaled(maxSide: 1200),
           let jpeg = scaled.jpegData(compressionQuality: 0.8) {
            onPhotoPicked(jpeg)
        }
    }

    /// Before the first expense: one line, one button. Alone in the group the button invites,
    /// because an expense needs somebody to split with; otherwise it adds the expense.
    private var fresh: some View {
        let canSplit = group.activeMembers.count >= 2
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Text("Inga utgifter än")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
                if photo == nil {
                    badge
                }
            }
            if canSplit {
                Button("Lägg till utgift", action: onAddExpense)
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Bjud in", action: onMembers)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settled: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("Ni är kvitt")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            if photo == nil {
                badge
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The nets to draw, shaped by the viewing mode. Exact by default; ≈ on request.
    private var displayedNets: [(money: Money, approximate: Bool)] {
        let nets = group.nets(for: userId, in: balances)
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
        let currencies = balances.currencies
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

// MARK: - The two views

/// The two ways to look at a group: what was spent, and where everyone stands.
enum GroupSegment: CaseIterable, Hashable {
    case expenses, standing

    var title: LocalizedStringKey {
        switch self {
        case .expenses: return "Utgifter"
        case .standing: return "Ställning"
        }
    }
}

/// The floating bar at the foot of a group: the segment toggle, and the plus. Glass, so it sits
/// where the app's tab bar sat and reads as the same kind of thing.
private struct GroupBottomBar: View {
    @Binding var segment: GroupSegment
    /// Alone in the group there is nobody to split with; the plus waits until there is.
    let canAdd: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(GroupSegment.allCases, id: \.self) { candidate in
                    let isOn = segment == candidate
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { segment = candidate }
                    } label: {
                        Text(candidate.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isOn ? Theme.ink : Theme.secondary)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 11)
                            .background(isOn ? Theme.ink.opacity(0.08) : .clear, in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(4)
            .glassEffect(.regular, in: .capsule)

            if canAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Theme.accent, in: .circle)
                }
                .buttonStyle(ScaleButtonStyle())
                .accessibilityLabel("Lägg till utgift")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

/// What a segment says when it has nothing to list: one line, and at most one button.
private struct EmptySegment: View {
    let text: LocalizedStringKey
    let button: (title: LocalizedStringKey, action: () -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Text(text)
                .font(.body)
                .foregroundStyle(Theme.secondary)
            if let button {
                Button(button.title, action: button.action)
                    .buttonStyle(PrimaryButtonStyle())
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Expense list

private struct ExpenseList: View {
    let group: GroupState
    /// Newest first, already narrowed to the segment (yours, or everyone else's).
    let expenses: [Expense]
    let meId: MemberID?
    let mode: CurrencyDisplay
    let onSelect: (ExpenseID) -> Void

    /// The only-mode filter narrows the list; native and ≈ modes always show every expense
    /// in its own currency — an expense is a fact, and facts do not convert.
    private var visibleUnderMode: [Expense] {
        if case .only(let currency) = mode {
            return expenses.filter { $0.currency == currency }
        }
        return expenses
    }

    var body: some View {
        // visibleExpenses is already newest-first; chunk into months preserving that order.
        let months = MonthGroup.group(visibleUnderMode)
        ForEach(months) { month in
            SectionHeader(title: month.title)
            LazyVStack(spacing: 0) {
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
            CategoryGlyph(categoryId: expense.categoryId)

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title).font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                Text(payerLine).font(.caption).foregroundStyle(Theme.secondary)
            }

            Spacer()

            NeutralAmountText(
                amountMinor: expense.amountMinor,
                currency: expense.currency,
                size: 16,
                explicit: expense.currency != group.currency
            )
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
            .font(.footnote)
            .textCase(.uppercase)
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 12)
    }
}
