import SwiftUI
import KvittaCore
import KvittaStorage

/// Who is in this group: add someone, rename them, remove them, or invite them to join.
///
/// Until now members could only be named while the group was being created, which meant a friend
/// who turned up on the second night of a trip could not be added at all. `MemberUpdated` (M4b)
/// is what makes renaming and linking possible; this is the screen that uses it.
struct MembersSheet: View {
    let ledger: LedgerStore
    let userId: UserID
    let groupId: GroupID
    let invites: InviteModel

    @Environment(\.dismiss) private var dismiss

    @State private var newName = ""
    @State private var renaming: MemberID?
    @State private var renamedTo = ""
    @State private var failure: String?

    private var group: GroupState? { ledger.state[groupId] }

    var body: some View {
        NavigationStack {
            Form {
                membersSection
                addSection
                inviteSection

                if let failure {
                    Section {
                        Text(failure).font(.footnote).foregroundStyle(Theme.clay)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground())
            .navigationTitle("Medlemmar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klar") { dismiss() }
                }
            }
            .alert("Byt namn", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("Namn", text: $renamedTo)
                Button("Spara") { commitRename() }
                Button("Avbryt", role: .cancel) { renaming = nil }
            }
        }
    }

    // MARK: - The list

    @ViewBuilder
    private var membersSection: some View {
        Section {
            ForEach(group?.activeMembers.sorted { $0.displayName < $1.displayName } ?? [], id: \.id) { member in
                HStack(spacing: 12) {
                    Avatar(name: member.displayName, size: 34)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.displayName).foregroundStyle(Theme.ink)
                        if member.linkedUserId != nil {
                            // The distinction §5 is built around: a linked member has the app and
                            // syncs; a placeholder is someone you are splitting with regardless.
                            Text("Har appen").font(.caption).foregroundStyle(Theme.sage)
                        } else {
                            Text("Ingen app än").font(.caption).foregroundStyle(Theme.secondary)
                        }
                    }

                    Spacer()
                }
                .swipeActions(edge: .trailing) {
                    // Removing yourself is not offered: you would lose the group from your own
                    // device while still owing money in it, which helps nobody.
                    if member.linkedUserId != userId {
                        Button("Ta bort", role: .destructive) { remove(member.id) }
                    }
                    Button("Byt namn") {
                        renamedTo = member.displayName
                        renaming = member.id
                    }
                    .tint(Theme.secondary)
                }
            }
        } footer: {
            Text("En borttagen medlem behåller sin historik — utgifter de var med på ändras inte.")
        }
    }

    private var addSection: some View {
        Section {
            HStack {
                TextField("Lägg till namn", text: $newName)
                Button("Lägg till", action: add)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } footer: {
            Text("Du kan lägga till någon som inte har appen. Utgifter fungerar likadant.")
        }
    }

    // MARK: - Inviting

    /// The share affordance. Without this the invite endpoint existed and nothing could reach it.
    @ViewBuilder
    private var inviteSection: some View {
        Section {
            if let invite = invites.pendingInvite {
                ShareLink(item: invite.url) {
                    Label("Dela inbjudningslänk", systemImage: "square.and.arrow.up")
                }
                Text(invite.url.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundStyle(Theme.secondary)
                    .textSelection(.enabled)
            } else {
                Button {
                    Task { await invites.createInvite(for: groupId) }
                } label: {
                    HStack {
                        Label("Skapa inbjudningslänk", systemImage: "link")
                        Spacer()
                        if invites.isWorking { ProgressView() }
                    }
                }
                .disabled(invites.isWorking)
            }

            if case .failed(let reason) = invites.outcome {
                Text(reason).font(.footnote).foregroundStyle(Theme.clay)
            }
        } header: {
            Text("Bjud in")
        } footer: {
            Text("Den som öppnar länken kan ta över en av platserna ovan och ser då hela historiken. Länken går ut efter två veckor.")
        }
    }

    // MARK: - Writes

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        perform {
            try ledger.record(
                .memberAdded(MemberAddedPayload(displayName: name)),
                entityId: MemberID().rawValue,
                in: groupId
            )
            newName = ""
        }
    }

    private func commitRename() {
        guard let memberId = renaming else { return }
        let name = renamedTo.trimmingCharacters(in: .whitespaces)
        renaming = nil
        guard !name.isEmpty else { return }

        perform {
            // Only the name. Absent fields mean unchanged, so this cannot accidentally detach
            // whoever the member is linked to.
            try ledger.record(
                .memberUpdated(MemberUpdatedPayload(displayName: name)),
                entityId: memberId.rawValue,
                in: groupId
            )
        }
    }

    private func remove(_ memberId: MemberID) {
        perform {
            try ledger.record(
                .memberRemoved(EmptyPayload()),
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
            // A failed local write stays on screen — never a silently lost change (CLAUDE.md).
            failure = String(describing: error)
        }
    }
}
