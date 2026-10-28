import SwiftUI
import KvittaCore
import KvittaStorage

/// INSTÄLLNINGAR (Steven 7/16, README §1.2 image 11): the group's name, its statistics, photo,
/// members, invite link, CSV export, archiving and leaving.
///
/// Unwired for now. #151 depends on Steven 3 (#147, `ArchivedGroupsStore`) and Steven 4 (#148,
/// the `UnderlineTabs` shell whose `•••` should push this screen), and both are still open PRs
/// (#163, #164) on top of `main`. This file is correct and self-contained — archiving is a
/// caller-supplied closure precisely so it does not need `ArchivedGroupsStore` to exist yet, the
/// same pattern #167/#166/#169 used for their own still-unwired tabs. Whoever lands #148 pushes
/// this from the `•••` button in place of today's `Menu`, passing a real `onArchive`/`onLeft`.
struct GroupSettingsView: View {
    let ledger: LedgerStore
    let userId: UserID
    let groupId: GroupID
    let invites: InviteModel
    let photos: GroupPhotoSyncer
    /// Archiving is device-local (`ArchivedGroupsStore`, Steven 3) and lives outside this file
    /// until #147 merges — the caller does the actual archiving.
    let onArchive: () -> Void
    /// Called once `MemberRemoved` for yourself has been written. The group this screen is about
    /// is no longer yours to look at, so the caller pops back out to the group list.
    let onLeft: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingMembers = false
    @State private var showingAddMember = false
    @State private var showingLink = false
    @State private var showingPhoto = false
    @State private var confirmingLeave = false
    @State private var expenseModel: NewExpenseModel?
    @State private var failure: String?

    private static let currencies: [CurrencyCode] = [.sek, .dkk, .nok, .eur]

    private var group: GroupState? { ledger.state[groupId] }

    var body: some View {
        if let group {
            content(for: group)
        } else {
            ContentUnavailableView("Gruppen finns inte längre", systemImage: "person.2.slash")
        }
    }

    private func content(for group: GroupState) -> some View {
        let meId = group.me(for: userId)?.id
        // The ledger-empty rule `GroupUpdatedPayload`/`Projector` already enforce server- and
        // client-side — shown here only when changing it would actually do anything.
        let currencyIsEditable = group.expenses.isEmpty && group.payments.isEmpty
        let canLeave = meId.map { id in
            group.balances().money(for: id).allSatisfy { $0.amountMinor == 0 }
        } ?? false

        return VStack(spacing: 0) {
            Steven.NavTitleBar(title: "Inställningar", leading: .back({ dismiss() }))
            ScrollView {
                VStack(spacing: 0) {
                    Steven.SectionHeader("Gruppnamn")
                    GroupNameRow(ledger: ledger, groupId: groupId, name: group.name, onError: fail)
                    if currencyIsEditable {
                        currencyRow(current: group.currency)
                    }
                    NavigationLink {
                        ReportsView(
                            ledger: ledger, userId: userId, groupId: groupId,
                            onOpenGroup: { _ in },
                            onAddExpense: {
                                expenseModel = NewExpenseModel(ledger: ledger, userId: userId, groupId: groupId)
                            }
                        )
                    } label: {
                        PlainRow(title: "Statistik") { Steven.Chevron() }
                    }
                    .buttonStyle(Steven.RowButtonStyle())

                    Button { showingPhoto = true } label: {
                        Steven.ListRow(icon: "photo", title: "Gruppbild", showsSeparator: false)
                    }
                    .buttonStyle(Steven.RowButtonStyle())

                    Steven.SectionHeader("Deltagare")
                    MembersSummaryRow(members: group.activeMembers, me: meId) { showingMembers = true }
                    Button { showingAddMember = true } label: {
                        Steven.ListRow(icon: "person.badge.plus", title: "Lägg till medlemmar")
                    }
                    .buttonStyle(Steven.RowButtonStyle())
                    Button { showingLink = true } label: {
                        Steven.ListRow(icon: "link", title: "Grupplänk", showsSeparator: false)
                    }
                    .buttonStyle(Steven.RowButtonStyle())

                    Steven.SectionHeader("General")
                    ShareLink(
                        item: CSVExportFile(group: group),
                        preview: SharePreview(CSVExportFile.filename(for: group))
                    ) {
                        Steven.ListRow(
                            icon: "square.and.arrow.up", title: "Exportera CSV",
                            trailing: .none, showsSeparator: false
                        )
                    }
                    .buttonStyle(Steven.RowButtonStyle())

                    Color.clear.frame(height: 32)

                    Button(action: onArchive) {
                        Steven.ListRow(icon: "archivebox", title: "Arkivera grupp", trailing: .none)
                    }
                    .buttonStyle(Steven.RowButtonStyle())

                    Button { confirmingLeave = true } label: {
                        Steven.ListRow(
                            icon: "rectangle.portrait.and.arrow.right", title: "Lämna grupp",
                            trailing: .none, showsSeparator: false
                        )
                    }
                    .buttonStyle(Steven.RowButtonStyle())
                    .disabled(!canLeave)
                    .opacity(canLeave ? 1 : 0.4)

                    if !canLeave {
                        Text("Du måste vara kvitt i alla valutor för att kunna lämna gruppen.")
                            .stevenFont(.footnote)
                            .foregroundStyle(StevenColor.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, StevenMetric.gutter)
                            .padding(.top, 8)
                    }

                    if let failure {
                        Text(failure)
                            .stevenFont(.footnote)
                            .foregroundStyle(StevenColor.owe)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, StevenMetric.gutter)
                            .padding(.top, 8)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(StevenColor.screen)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingMembers) {
            GroupMembersListView(ledger: ledger, userId: userId, groupId: groupId)
        }
        .sheet(isPresented: $showingAddMember) {
            AddMemberSheet(ledger: ledger, groupId: groupId)
        }
        .sheet(isPresented: $showingLink) {
            GroupLinkSheet(invites: invites, groupId: groupId)
        }
        .sheet(isPresented: $showingPhoto) {
            GroupPhotoViewer(groupName: group.name, groupId: groupId, photos: photos)
        }
        .sheet(item: $expenseModel) { model in
            NewExpenseSheet(model: model)
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "Lämna gruppen?",
            isPresented: $confirmingLeave,
            titleVisibility: .visible
        ) {
            Button("Lämna", role: .destructive, action: leave)
        } message: {
            Text("Du tas bort ur gruppen. Det går inte att ångra.")
        }
    }

    /// Our own addition — Steven has no multi-currency concept (§4). Kept a plain row rather
    /// than `Steven.ListRow` because this row has no leading icon in image 11's layout either.
    private func currencyRow(current: CurrencyCode) -> some View {
        Menu {
            Picker("Valuta", selection: Binding(get: { current }, set: changeCurrency)) {
                ForEach(Self.currencies, id: \.self) { currency in
                    Text(verbatim: currency.code).tag(currency)
                }
            }
        } label: {
            PlainRow(title: "Valuta") {
                HStack(spacing: 8) {
                    Text(verbatim: current.code).stevenFont(.rowTitle).foregroundStyle(StevenColor.muted)
                    Steven.Chevron()
                }
            }
        }
    }

    private func changeCurrency(_ new: CurrencyCode) {
        do {
            try ledger.record(
                .groupUpdated(GroupUpdatedPayload(currency: new)),
                entityId: groupId.rawValue,
                in: groupId
            )
            failure = nil
        } catch {
            fail(String(describing: error))
        }
    }

    private func leave() {
        guard let meId = group?.me(for: userId)?.id else { return }
        do {
            try ledger.record(.memberRemoved(EmptyPayload()), entityId: meId.rawValue, in: groupId)
            failure = nil
            onLeft()
        } catch {
            fail(String(describing: error))
        }
    }

    private func fail(_ message: String) {
        failure = message
    }
}

// MARK: - Rows with no leading icon

/// A `Steven.ListRow` twin for the rows image 11 draws with nothing in the icon column — the
/// name, Statistik and the currency row all start flush with the section header above them,
/// where the icon rows (Gruppbild, Lägg till medlemmar, …) indent past their glyph.
private struct PlainRow<Trailing: View>: View {
    let title: LocalizedStringKey
    var showsSeparator = true
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            Text(title).stevenFont(.rowTitle).foregroundStyle(StevenColor.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, StevenMetric.gutter)
        .padding(.vertical, 8)
        .frame(minHeight: StevenMetric.rowHeight)
        .contentShape(.rect)
        .overlay(alignment: .bottom) {
            if showsSeparator { Steven.Hairline(color: StevenColor.rowSeparator) }
        }
    }
}

/// GRUPPNAMN's own row — editable right in the row, since image 11 shows no separate edit
/// affordance **[gissning]**. Commits on Return or on losing focus; never on every keystroke.
private struct GroupNameRow: View {
    let ledger: LedgerStore
    let groupId: GroupID
    let name: String
    let onError: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Namn", text: $draft)
            .stevenFont(.rowTitle)
            .foregroundStyle(StevenColor.ink)
            .focused($focused)
            .submitLabel(.done)
            .onSubmit(commit)
            .padding(.horizontal, StevenMetric.gutter)
            .padding(.vertical, 8)
            .frame(minHeight: StevenMetric.rowHeight)
            .overlay(alignment: .bottom) { Steven.Hairline(color: StevenColor.rowSeparator) }
            .onAppear { draft = name }
            .onChange(of: name) { _, updated in if !focused { draft = updated } }
            .onChange(of: focused) { was, isNow in if was && !isNow { commit() } }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != name else {
            draft = name
            return
        }
        do {
            try ledger.record(
                .groupUpdated(GroupUpdatedPayload(name: trimmed)),
                entityId: groupId.rawValue,
                in: groupId
            )
        } catch {
            draft = name
            onError(String(describing: error))
        }
    }
}

/// DELTAGARE's own row: the avatar stack and a count, both from image 11. Avatars read their
/// photos straight from the environment (`Steven.AvatarView`), so this needs no profile data.
private struct MembersSummaryRow: View {
    let members: [Member]
    let me: MemberID?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Steven.AvatarStack(members: members, me: me)
                Spacer(minLength: 8)
                Text(verbatim: "\(members.count)")
                    .stevenFont(.rowTitle)
                    .foregroundStyle(StevenColor.muted)
                Steven.Chevron()
            }
            .padding(.horizontal, StevenMetric.gutter)
            .padding(.vertical, 8)
            .frame(minHeight: StevenMetric.rowHeight)
            .contentShape(.rect)
            .overlay(alignment: .bottom) { Steven.Hairline(color: StevenColor.rowSeparator) }
        }
        .buttonStyle(Steven.RowButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Deltagare") + Text(verbatim: ", \(members.count)"))
    }
}

// MARK: - Medlemslista

/// The DELTAGARE row's destination: every active member, Steven list rows, the same rename/
/// remove/"Har appen" functions `MembersSheet` already has. A separate screen rather than a
/// restyle of that file, which the old `•••` menu still opens until #148's shell replaces it.
struct GroupMembersListView: View {
    let ledger: LedgerStore
    let userId: UserID
    let groupId: GroupID

    @Environment(\.dismiss) private var dismiss
    @State private var renaming: MemberID?
    @State private var renamedTo = ""
    @State private var failure: String?

    private var group: GroupState? { ledger.state[groupId] }

    private var meId: MemberID? { group?.me(for: userId)?.id }

    private var sortedMembers: [Member] {
        (group?.activeMembers ?? []).sorted { left, right in
            if left.id == meId { return true }
            if right.id == meId { return false }
            return left.displayName < right.displayName
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Steven.NavTitleBar(title: "Medlemmar", leading: .close({ dismiss() }))
            List {
                ForEach(sortedMembers) { member in
                    row(for: member)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(StevenColor.surface)
                        .swipeActions(edge: .trailing) {
                            // Removing yourself would lose the group from your own device while
                            // still owing money in it — "Lämna grupp" is the one way out for you.
                            if member.linkedUserId != userId {
                                Button("Ta bort", role: .destructive) { remove(member.id) }
                            }
                            Button("Byt namn") {
                                renamedTo = member.displayName
                                renaming = member.id
                            }
                            .tint(StevenColor.muted)
                        }
                }
                if let failure {
                    Text(failure)
                        .stevenFont(.footnote)
                        .foregroundStyle(StevenColor.owe)
                        .listRowSeparator(.hidden)
                        .listRowBackground(StevenColor.screen)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(StevenColor.screen)
        }
        .background(StevenColor.screen)
        .alert("Byt namn", isPresented: Binding(
            get: { renaming != nil },
            set: { if !$0 { renaming = nil } }
        )) {
            TextField("Namn", text: $renamedTo)
            Button("Spara", action: commitRename)
            Button("Avbryt", role: .cancel) { renaming = nil }
        }
    }

    private func row(for member: Member) -> some View {
        HStack(spacing: 16) {
            Steven.AvatarView(member: member, isMe: member.id == meId)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: member.displayName).stevenFont(.rowTitle).foregroundStyle(StevenColor.ink)
                Text(member.linkedUserId != nil ? "Har appen" : "Ingen app än")
                    .stevenFont(.footnote)
                    .foregroundStyle(member.linkedUserId != nil ? StevenColor.accent : StevenColor.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, StevenMetric.gutter)
        .padding(.vertical, 8)
        .frame(minHeight: StevenMetric.rowHeight)
        .overlay(alignment: .bottom) { Steven.Hairline(color: StevenColor.rowSeparator) }
    }

    private func remove(_ memberId: MemberID) {
        perform {
            try ledger.record(.memberRemoved(EmptyPayload()), entityId: memberId.rawValue, in: groupId)
        }
    }

    private func commitRename() {
        guard let memberId = renaming else { return }
        let name = renamedTo.trimmingCharacters(in: .whitespaces)
        renaming = nil
        guard !name.isEmpty else { return }
        perform {
            try ledger.record(
                .memberUpdated(MemberUpdatedPayload(displayName: name)),
                entityId: memberId.rawValue,
                in: groupId
            )
        }
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            failure = nil
        } catch {
            failure = String(describing: error)
        }
    }
}

// MARK: - Lägg till medlemmar

/// The friend who will never install the app — same `MemberAdded` write `MembersSheet` already
/// makes, in its own small sheet since image 11 gives it its own row rather than an inline field.
private struct AddMemberSheet: View {
    let ledger: LedgerStore
    let groupId: GroupID

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 0) {
            Steven.NavTitleBar(title: "Lägg till medlemmar", leading: .close({ dismiss() }))
            VStack(alignment: .leading, spacing: 16) {
                Steven.Card(padding: 0) {
                    TextField("Lägg till namn", text: $name)
                        .stevenFont(.rowTitle)
                        .submitLabel(.done)
                        .onSubmit(add)
                        .padding(.horizontal, StevenMetric.gutter)
                        .frame(minHeight: StevenMetric.formRowHeight)
                }
                if let failure {
                    Text(failure).stevenFont(.footnote).foregroundStyle(StevenColor.owe)
                }
                Button("Lägg till", action: add)
                    .buttonStyle(Steven.FilledButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(StevenMetric.gutter)
            Spacer(minLength: 0)
        }
        .background(StevenColor.screen)
    }

    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try ledger.record(
                .memberAdded(MemberAddedPayload(displayName: trimmed)),
                entityId: MemberID().rawValue,
                in: groupId
            )
            name = ""
            failure = nil
        } catch {
            failure = String(describing: error)
        }
    }
}

// MARK: - Grupplänk

/// "Grupplänk" (image 11): the same create-invite-and-share flow `MembersSheet` already has, in
/// its own sheet so the settings list stays one row per destination.
private struct GroupLinkSheet: View {
    let invites: InviteModel
    let groupId: GroupID

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Steven.NavTitleBar(title: "Grupplänk", leading: .close({ dismiss() }))
            VStack(alignment: .leading, spacing: 12) {
                if let invite = invites.pendingInvite {
                    ShareLink(item: invite.url) {
                        Steven.ListRow(icon: "square.and.arrow.up", title: "Dela inbjudningslänk", trailing: .none)
                    }
                    Text(verbatim: invite.url.absoluteString)
                        .stevenFont(.footnote)
                        .foregroundStyle(StevenColor.muted)
                        .textSelection(.enabled)
                        .padding(.horizontal, StevenMetric.gutter)
                } else {
                    Button {
                        Task { await invites.createInvite(for: groupId) }
                    } label: {
                        Steven.ListRow(icon: "link", title: "Skapa inbjudningslänk", trailing: .none, showsSeparator: false)
                    }
                    .buttonStyle(Steven.RowButtonStyle())
                    .disabled(invites.isWorking)
                }
                if case .failed(let reason) = invites.outcome {
                    Text(reason)
                        .stevenFont(.footnote)
                        .foregroundStyle(StevenColor.owe)
                        .padding(.horizontal, StevenMetric.gutter)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
        }
        .background(StevenColor.screen)
    }
}
