import SwiftUI

/// Joining a group from a pasted invite, for when the link itself did not survive the trip.
///
/// Tapping the link is the normal path and needs no UI at all. This exists because links get
/// mangled — forwarded through chat apps, screenshotted, read out loud — and a group you cannot
/// join because a URL lost its scheme is a bad afternoon. It takes the bare token too. It sits
/// under the Grupper title next to "Ny grupp", because that is where somebody holding an invite
/// goes looking; it used to be a section on Jag, where nobody found it.
struct JoinGroupSheet: View {
    let invites: InviteModel

    @Environment(\.dismiss) private var dismiss
    @State private var inviteCode = ""

    private var canJoin: Bool { !inviteCode.isEmpty && !invites.isWorking }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Klistra in inbjudningskod", text: $inviteCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Länken du fick, eller bara koden i den — båda fungerar.")
                }

                switch invites.outcome {
                case .failed(let reason):
                    Section {
                        Text(reason).font(.footnote).foregroundStyle(Theme.clay)
                    }
                case .joined, nil:
                    EmptyView()
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground())
            .navigationTitle("Gå med i grupp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if invites.isWorking {
                        ProgressView()
                    } else {
                        Button("Gå med", action: join).disabled(!canJoin)
                    }
                }
            }
            // A stale "failed" from an earlier attempt would greet the next one.
            .onAppear { invites.clear() }
        }
    }

    private func join() {
        Task {
            await invites.accept(rawCode: inviteCode)
            // The group is in the ledger now and shows up on Grupper behind this sheet — the sheet
            // has nothing left to say.
            if case .joined = invites.outcome { dismiss() }
        }
    }
}
