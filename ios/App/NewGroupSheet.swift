import SwiftUI
import KvittaCore
import KvittaStorage

/// Creating a group: a name, a currency, and you.
///
/// It used to ask you to type everybody's names up front, which is the wrong shape twice over —
/// it is work before you have got anything, and the names you invent are then the names your
/// friends are stuck with when they join. Now the group starts with you and fills up from the
/// invite link, and creating it hands you straight into the group so the link is the next thing
/// you see.
///
/// Adding someone by name did not go away, it moved: `MembersSheet` still does it, for the person
/// who will never install the app. That is design doc §5's "single most important UX decision" and
/// it is not up for removal — it is just no longer the price of making a group.
struct NewGroupSheet: View {
    let ledger: LedgerStore
    let userId: UserID
    let profile: UserProfile
    var onCreated: (GroupID) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var currency: CurrencyCode = .sek
    @State private var failure: String?

    private static let currencies: [CurrencyCode] = [.sek, .dkk, .nok, .eur]

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Grupp") {
                    TextField("Namn (t.ex. 🏔️ Fjällresan)", text: $name)
                    Picker("Valuta", selection: $currency) {
                        ForEach(Self.currencies, id: \.self) { code in
                            Text(MoneyFormat.symbol(code) == code.code ? code.code
                                 : "\(code.code) · \(MoneyFormat.symbol(code))").tag(code)
                        }
                    }
                }

                Section {
                    HStack(spacing: 12) {
                        Avatar(name: profile.nameOrDefault, photo: profile.avatarData, size: 34)
                        Text(profile.nameOrDefault).foregroundStyle(Theme.ink)
                        Spacer()
                    }
                } header: {
                    Text("Medlemmar")
                } footer: {
                    Text("Du är ensam i gruppen till att börja med. Dela inbjudningslänken så går de andra med själva — då väljer de sina egna namn.")
                }

                if let failure {
                    Section {
                        Text(failure).font(.footnote).foregroundStyle(Theme.clay)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground())
            .navigationTitle("Ny grupp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Skapa", action: create).disabled(!canCreate)
                }
            }
        }
    }

    private func create() {
        do {
            let groupId = GroupID()
            try ledger.record(
                .groupCreated(GroupCreatedPayload(name: name.trimmingCharacters(in: .whitespaces), currency: currency)),
                entityId: groupId.rawValue, in: groupId
            )
            // The Jag tab promises your name "visas som du i nya grupper". This is where that
            // promise is kept; before, the sheet had its own field defaulting to "Du" and the
            // profile name was never read.
            try ledger.record(
                .memberAdded(MemberAddedPayload(
                    displayName: profile.nameOrDefault,
                    linkedUserId: userId
                )),
                entityId: MemberID().rawValue, in: groupId
            )
            onCreated(groupId)
            dismiss()
        } catch {
            // A local write failing must surface, never vanish (CLAUDE.md).
            failure = String(describing: error)
        }
    }
}
