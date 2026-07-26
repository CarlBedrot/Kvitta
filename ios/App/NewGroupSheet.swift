import SwiftUI
import KvittaCore
import KvittaStorage

/// Creating a group. Every field goes to the log through `LedgerStore.record` — one
/// `GroupCreated`, then a `MemberAdded` for "Du" linked to this device, then one per other
/// person. No money yet, so there is nothing to validate beyond having a name and someone to
/// split with.
struct NewGroupSheet: View {
    let ledger: LedgerStore
    let userId: UserID
    var onCreated: (GroupID) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var currency: CurrencyCode = .sek
    @State private var youName = "Du"
    @State private var others: [String] = ["", ""]
    @State private var failure: String?

    private static let currencies: [CurrencyCode] = [.sek, .dkk, .nok, .eur]

    private var trimmedOthers: [String] {
        others.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !youName.trimmingCharacters(in: .whitespaces).isEmpty
            && !trimmedOthers.isEmpty
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

                MemberFieldsSection(youName: $youName, others: $others)

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
            let meId = MemberID()
            try ledger.record(
                .memberAdded(MemberAddedPayload(
                    displayName: youName.trimmingCharacters(in: .whitespaces),
                    linkedUserId: userId
                )),
                entityId: meId.rawValue, in: groupId
            )
            for other in trimmedOthers {
                let memberId = MemberID()
                try ledger.record(
                    .memberAdded(MemberAddedPayload(displayName: other)),
                    entityId: memberId.rawValue, in: groupId
                )
            }
            onCreated(groupId)
            dismiss()
        } catch {
            // A local write failing must surface, never vanish (CLAUDE.md).
            failure = String(describing: error)
        }
    }
}

/// The member name fields: you (linked) plus a growable list of the others.
private struct MemberFieldsSection: View {
    @Binding var youName: String
    @Binding var others: [String]

    var body: some View {
        Section("Medlemmar") {
            HStack {
                Text("Du").foregroundStyle(Theme.secondary).frame(width: 44, alignment: .leading)
                TextField("Ditt namn", text: $youName)
            }
            ForEach(others.indices, id: \.self) { index in
                TextField("Namn", text: $others[index])
            }
            .onDelete { others.remove(atOffsets: $0) }

            Button("Lägg till person", systemImage: "plus") {
                others.append("")
            }
        }
    }
}
