import SwiftUI

struct ProfileEditorView: View {
    @Bindable var profile: UserProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Avatar(name: profile.nameOrDefault, photo: profile.avatarData, size: 88)
                        .frame(maxWidth: .infinity)
                    field("Namn") {
                        TextField("Ditt namn", text: $profile.displayName)
                            .textContentType(.name)
                            .sliceField(invalid: profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    field("Swish-nummer") {
                        TextField("07XX XXX XX XX", text: $profile.swishNumber)
                            .keyboardType(.phonePad)
                            .sliceField()
                    }
                    Text("Ditt namn används i nya grupper. När du är inloggad delas ditt Swish-nummer med gruppmedlemmarna så att de kan betala dig.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
                .padding(20)
            }
            .background(AmbientBackground())
            .navigationTitle("Redigera profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Klar") { dismiss() } }
            }
        }
    }

    private func field<Content: View>(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
            content()
        }
    }
}
