import SwiftUI
import KvittaCore

/// Mer → Mina detaljer (07): a Steven form card, read-only until tapped. One editor behind every
/// row — profile picture, name and phone are a single form (`ProfileEditorView`), the same one
/// onboarding shows, because splitting them into three editors would be three places to keep the
/// same validation in sync.
struct MinaDetaljerView: View {
    let profile: UserProfile
    let session: SessionModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var editing = false
    @State private var confirmingDelete = false

    var body: some View {
        VStack(spacing: 0) {
            Steven.NavTitleBar(title: "Mina detaljer", leading: .back { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: StevenMetric.gutter * 2) {
                    Button { editing = true } label: {
                        Steven.Card(padding: 0) {
                            VStack(spacing: 0) {
                                Steven.FormRow(label: "Profilbild") {
                                    Avatar(name: profile.nameOrDefault, photo: profile.avatarData,
                                           size: StevenMetric.avatarRow)
                                }
                                Steven.FormRow(label: "Namn", value: profile.nameOrDefault)
                                Steven.FormRow(label: "Telefon", value: profile.paymentPhone?.international ?? "—",
                                               showsSeparator: false)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if session.isSignedIn {
                        VStack(alignment: .leading, spacing: 16) {
                            Button("Logga ut") {
                                Task { await session.signOut() }
                            }
                            .buttonStyle(Steven.OutlineButtonStyle())
                            .textCase(.uppercase)

                            deleteAccountLink
                        }
                    }
                }
                .padding(StevenMetric.gutter)
            }
        }
        .background(StevenColor.screen)
        .navigationBarHidden(true)
        .sheet(isPresented: $editing) {
            ProfileEditorView(profile: profile)
        }
    }

    /// No account-deletion endpoint exists yet (#157 keeps it that way). A confirmation that
    /// hands off to email is honest about that, rather than a button that quietly does nothing —
    /// or, worse, one that looks real and is not wired to anything.
    private var deleteAccountLink: some View {
        Button {
            confirmingDelete = true
        } label: {
            Text("ta bort mitt Slicekonto")
                .underline()
                .stevenFont(.footnote)
                .foregroundStyle(StevenColor.muted)
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            Text("ta bort mitt Slicekonto"),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Skriv till oss") {
                openURL(URL(string: "mailto:?subject=Ta%20bort%20mitt%20Slicekonto")!)
            }
        } message: {
            Text("Det finns ännu ingen knapp som gör det automatiskt. Vi öppnar ett mejl i stället, så tar vi bort kontot manuellt.")
        }
    }
}
