import SwiftUI
import KvittaCore
import PhotosUI

/// The one editor behind every row of `MinaDetaljerView`, and — with `required: true` — the
/// fullscreen cover onboarding shows before the app will let you in at all (`RootView`). Same
/// form, same validation, either way; only the title, the button label and whether "Avbryt"
/// exists change.
struct ProfileEditorView: View {
    let profile: UserProfile
    var required = false
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var number: String
    @State private var country: PaymentPhoneNumber.Country
    @State private var photoItem: PhotosPickerItem?

    init(profile: UserProfile, required: Bool = false) {
        self.profile = profile
        self.required = required
        _name = State(initialValue: profile.displayName)
        _country = State(initialValue: profile.paymentPhone?.country ?? .sweden)
        _number = State(initialValue: profile.paymentPhone.map { String($0.digits.dropFirst(2)) } ?? profile.swishNumber)
    }

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && PaymentPhoneNumber(number, country: country) != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Steven.NavTitleBar(
                    title: required ? "Din profil" : "Redigera profil",
                    leading: required ? .none : .close { dismiss() }
                )
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        photoPicker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Namn").stevenFont(.rowTitleBold).foregroundStyle(StevenColor.ink)
                            TextField("Ditt namn", text: $name)
                                .textContentType(.name)
                                .sliceField()
                        }
                        PaymentPhoneFields(number: $number, country: $country)
                        Text("Ange numret du använder för Swish eller MobilePay. Det delas med dina gruppmedlemmar när du är inloggad.")
                            .stevenFont(.footnote)
                            .foregroundStyle(StevenColor.muted)
                        Button(required ? "Fortsätt" : "Spara") {
                            if profile.save(name: name, phone: number, country: country) { dismiss() }
                        }
                        .buttonStyle(Steven.FilledButtonStyle())
                        .disabled(!valid)
                    }
                    .padding(StevenMetric.gutter)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(StevenColor.screen)
            .navigationBarHidden(true)
            .task(id: photoItem) { await loadPhoto() }
        }
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                Avatar(name: name, photo: profile.avatarData, size: StevenMetric.avatarHero)
                Image(systemName: "camera.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(StevenColor.accentFill, in: .circle)
                    .overlay(Circle().strokeBorder(StevenColor.surface, lineWidth: 2))
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func loadPhoto() async {
        guard let photoItem else { return }
        // Downscaled before storing: a full-resolution camera image in UserDefaults would be
        // several megabytes read back on every launch.
        if let data = try? await photoItem.loadTransferable(type: Data.self),
           let square = UIImage(data: data)?.squareThumbnail(side: 256),
           let jpeg = square.jpegData(compressionQuality: 0.85) {
            profile.avatarData = jpeg
        }
    }
}

/// Used for your profile and for a recipient whose profile is not available yet.
struct PaymentPhoneFields: View {
    @Binding var number: String
    @Binding var country: PaymentPhoneNumber.Country

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Telefonnummer").font(.subheadline.weight(.semibold))
            Picker("Land", selection: $country) {
                Text("Sverige +46").tag(PaymentPhoneNumber.Country.sweden)
                Text("Danmark +45").tag(PaymentPhoneNumber.Country.denmark)
            }
            .pickerStyle(.segmented)
            TextField(country == .sweden ? "070 123 45 67" : "20 12 34 56", text: $number)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .sliceField()
                .accessibilityLabel("Telefonnummer")
            if !number.isEmpty && PaymentPhoneNumber(number, country: country) == nil {
                Text("Kontrollera numret och landskoden.")
                    .font(.footnote)
                    .foregroundStyle(Theme.negative)
            }
        }
        .onChange(of: number) { _, value in
            if let parsed = PaymentPhoneNumber(value, country: country) { country = parsed.country }
        }
        .onChange(of: country) { old, new in
            // A deliberate country switch must not be silently overridden by the old prefix.
            if let parsed = PaymentPhoneNumber(number, country: old), parsed.country != new {
                number = String(parsed.digits.dropFirst(2))
            }
        }
    }
}

struct RecipientPhoneEditor: View {
    let initialNumber: String?
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""
    @State private var country: PaymentPhoneNumber.Country = .sweden

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PaymentPhoneFields(number: $number, country: $country)
                    Text("Sparas bara på den här telefonen, inte i gruppen.")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                    Button("Spara") {
                        guard let phone = PaymentPhoneNumber(number, country: country) else { return }
                        onSave(phone.digits)
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(PaymentPhoneNumber(number, country: country) == nil)
                }
                .padding(20)
            }
            .background(AmbientBackground())
            .navigationTitle("Mottagarens nummer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Avbryt") { dismiss() } }
            }
            .onAppear {
                if let initialNumber, let parsed = PaymentPhoneNumber(initialNumber) {
                    country = parsed.country
                    number = String(parsed.digits.dropFirst(2))
                }
            }
        }
        .tint(Theme.accent)
    }
}
