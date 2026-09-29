import SwiftUI
import KvittaCore
import KvittaStorage
import KvittaSync
import PhotosUI

/// Jag: who you are, and whether your data is safe. Nothing else.
///
/// This screen used to be a diagnostics panel — event counts, a "sync" switch, developer buttons —
/// because it was the only place to put them while the app was being built. None of that belongs
/// in front of a person. "Väntar på push" is a queue depth; "överhoppade händelser" should always
/// be zero and is a bug report when it is not. They now live behind a section that only exists in
/// debug builds — and even there stays hidden until seven taps on the version row ask for it,
/// because every build that reaches a phone today *is* a debug build. What is left says one
/// thing: is everything saved.
struct JagView: View {
    let ledger: LedgerStore
    let sync: SyncEngine
    @Bindable var profile: UserProfile
    let session: SessionModel
    let reminders: ReminderScheduler
    let rates: RateStore
    let userId: UserID

    @State private var photoItem: PhotosPickerItem?
    @State private var failure: String?
    @State private var editingProfile = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #if DEBUG
    @State private var serverAddress = UserDefaults.standard.string(forKey: "se.kvitta.syncBaseURL") ?? ""
    @State private var trialKey = UserDefaults.standard.string(forKey: SyncSettings.trialKeyDefaultsKey) ?? ""
    // Compile-time gating alone stopped meaning "developers only" the day the app reached real
    // phones: every build anyone actually runs is a Debug build (Xcode sideload, simulator) and
    // will be until TestFlight exists. So even in Debug the toolbox hides until deliberately
    // asked for — seven taps on the version row, the same ritual every phone OS taught people.
    @AppStorage("se.kvitta.devToolsVisible") private var devToolsVisible = false
    @State private var versionTaps = 0
    #endif

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PageHeader(title: "Profil", profile: profile, onProfile: { editingProfile = true })
                    .padding(20)
                ScrollView {
                    Group {
                        if horizontalSizeClass == .regular {
                            HStack(alignment: .top, spacing: 24) {
                                VStack(alignment: .leading, spacing: 18) {
                                    profileSection
                                    aboutSection
                                    helpSection
                                }
                                .frame(maxWidth: 520, alignment: .topLeading)
                                VStack(alignment: .leading, spacing: 18) {
                                    settingsSection
                                    accountSection
                                    logoutSection
                                }
                                .frame(maxWidth: 520, alignment: .topLeading)
                            }
                            .frame(maxWidth: 1080, alignment: .topLeading)
                        } else {
                            VStack(alignment: .leading, spacing: 18) {
                                profileSection
                                settingsSection
                                accountSection
                                aboutSection
                                helpSection
                                logoutSection
                            }
                        }
                    #if DEBUG
                        if devToolsVisible {
                            developerSection
                        }
                    #endif
                        if let failure {
                            noticePanel(failure)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 36)
                }
            }
            .background(AmbientBackground())
            // The tab bar floats over the bottom of the list. Without this the last row can only
            // ever be read through glass; with it the list scrolls a little further so every row
            // gets clear air at the bottom of the scroll.
            .contentMargins(.bottom, 32, for: .scrollContent)
            .navigationBarHidden(true)
            .task(id: photoItem) { await loadPhoto() }
            .sheet(isPresented: $editingProfile) {
                ProfileEditorView(profile: profile)
            }
        }
    }

    // MARK: - Profile

    @ViewBuilder
    @MainActor
    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        Avatar(name: profile.nameOrDefault, photo: profile.avatarData, size: 72)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Theme.accent, in: .circle)
                            .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.nameOrDefault)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Button("Redigera profil") { editingProfile = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .overlay(Capsule().stroke(Theme.ink, lineWidth: 1))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)

            if profile.avatarData != nil {
                Button("Ta bort bild", role: .destructive) {
                    profile.avatarData = nil
                    photoItem = nil
                }
                .padding(.horizontal, 4)
            }
            }

    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            outlinedPanel {
                VStack(alignment: .leading, spacing: 12) {
                    panelTitle("Inställningar")
                    swishNumberSection
                    Divider().overlay(Theme.hairline)
                    remindersSection
                }
            }
        }
    }

    private var swishNumberSection: some View {
        Button { editingProfile = true } label: {
            SettingsRow(systemImage: "phone", fill: Theme.accent, title: "Telefonnummer") {
                Text(profile.paymentPhone?.international ?? "—")
                    .foregroundStyle(Theme.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Redigera profil")
    }

    // MARK: - Account

    /// Signing in is optional and the copy says so.
    ///
    /// The app works completely without an account — that is the premise, not a limitation — so
    /// this section offers one benefit and never nags. It is also the only place the difference
    /// between "on this phone" and "safe if you lose this phone" is stated plainly.
    @ViewBuilder
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelTitle("Konto")
            outlinedPanel {
            if session.isSignedIn {
                SettingsRow(systemImage: "person.crop.circle.fill", fill: Theme.positive, title: "Inloggad") {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.positive)
                }

            } else {
                Button {
                    Task { await session.signIn(displayName: profile.displayName) }
                } label: {
                    SettingsRow(systemImage: "person.crop.circle.fill", fill: Theme.accent, title: "Logga in") {
                        if session.isWorking { ProgressView() }
                    }
                }
                .disabled(session.isWorking)
            }

            if let failure = session.failure {
                Text(failure).font(.footnote).foregroundStyle(Theme.clay)
            }

            if !ledger.rejectedPushes.isEmpty {
                // Design doc §7: rejected events are surfaced, never dropped. The only line
                // about the server that earns a place here: something of yours did not save.
                NavigationLink {
                    RejectedPushList(ledger: ledger)
                } label: {
                    HStack {
                        Text("Kunde inte sparas hos servern")
                        Spacer()
                        Text("\(ledger.rejectedPushes.count)").foregroundStyle(Theme.clay)
                    }
                }
            }
            }
        }
    }

    // MARK: - Reminders

    /// A weekly nudge about money you owe.
    ///
    /// Computed on the phone from the ledger it already has, so it works with no network and no
    /// account — unlike the APNs push in the same milestone, which needs a paid Apple Developer
    /// team and could not be built at all.
    @ViewBuilder
    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow(systemImage: "bell.badge", fill: Theme.accent, title: "Påminn mig om skulder") {
                Toggle("Påminn mig om skulder", isOn: Binding(
                    get: { reminders.isEnabled },
                    set: { on in Task { await reminders.setEnabled(on, ledger: ledger, userId: userId) } }
                ))
                .labelsHidden()
            }
            if reminders.wasDenied {
                Text("Notiser är avstängda för Slice i Inställningar.")
                    .font(.footnote)
                    .foregroundStyle(Theme.clay)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - About

    /// Version and build straight from the bundle — no hand-maintained copy to go stale.
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelTitle("Om Slice")
            outlinedPanel {
            HStack {
                SettingsIcon(systemImage: "info.circle.fill", fill: Color(hex: 0xA5A099))
                LabeledContent(
                    "Version",
                    value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))"
                )
            }
            #if DEBUG
            // The door into the developer section. Seven taps, counted per visit to this
            // screen — no timer, no feedback until the section simply appears below.
            .contentShape(.rect)
            .onTapGesture {
                guard !devToolsVisible else { return }
                versionTaps += 1
                if versionTaps >= 7 {
                    versionTaps = 0
                    devToolsVisible = true
                }
            }
            #endif
            }
        }
    }

    // MARK: - Help

    /// The escape hatch for "something looks wrong on my phone": a shareable state report.
    /// Not debug-gated — the whole point is that a friend on a release build can send one.
    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelTitle("Hjälp & information")
            outlinedPanel {
                ShareLink(item: DiagnosticReport.text(
                    ledger: ledger, sync: sync, rates: rates, signedIn: session.isSignedIn
                )) {
                    HStack {
                        SettingsIcon(systemImage: "ladybug", fill: Theme.secondary)
                        Text("Dela felrapport").foregroundStyle(Theme.ink)
                    }
                }
            }
        }
    }

    private var logoutSection: some View {
        Group {
            if session.isSignedIn {
                Button("Logga ut", role: .destructive) {
                    Task { await session.signOut() }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
        }
    }

    private func outlinedPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card.opacity(0.55), in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Theme.hairline, lineWidth: 1)
            }
    }

    private func panelTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 4)
    }

    private func noticePanel(_ message: String) -> some View {
        outlinedPanel {
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.clay)
        }
    }

    // MARK: - Developer

    #if DEBUG
    /// Only compiled into debug builds. These are the counters that used to confuse the front of
    /// this screen: a queue depth, and two numbers that are only interesting when non-zero.
    private var developerSection: some View {
        Section("Utvecklarverktyg") {
            Toggle("Synka med servern", isOn: Binding(
                get: { sync.isEnabled },
                set: { enabled in
                    SyncSettings.setEnabled(enabled)
                    if enabled { Task { await sync.syncAll() } }
                }
            ))
            Button("Synka nu", systemImage: "arrow.triangle.2.circlepath") {
                Task { await sync.syncAll() }
            }
            // For the sideloaded-to-a-friend's-phone trial: their phone must reach the dev
            // backend on your Mac's LAN address, not its own localhost. Read at launch
            // (Bootstrap.syncConfiguration), hence the restart note.
            // Label above the field, not beside it: on a real phone the side-by-side version
            // left the field a few points wide and effectively untappable, which read as "the
            // address cannot be changed". Saving happens on every keystroke rather than only on
            // .onSubmit, because the URL keyboard's return key is easy to miss and a typed but
            // unsaved address looks identical to a saved one.
            VStack(alignment: .leading, spacing: 4) {
                Text("Serveradress")
                TextField("", text: $serverAddress, prompt: Text("http://192.168.x.x:5142").placeholderStyle())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: serverAddress) { _, value in
                        let trimmed = value.trimmingCharacters(in: .whitespaces)
                        if trimmed.isEmpty {
                            UserDefaults.standard.removeObject(forKey: "se.kvitta.syncBaseURL")
                        } else if URL(string: trimmed) != nil {
                            UserDefaults.standard.set(trimmed, forKey: "se.kvitta.syncBaseURL")
                        }
                    }
            }
            // The hosted trial server keeps the dev sign-in on behind a shared key (Auth:TrialKey
            // on the server). A phone without it gets a bare 401 on "Logga in", which is the
            // intended answer to a stranger and a confusing one to a friend who was never given
            // the key — hence a field, not a launch argument. Saved on every keystroke for the
            // same reason as the address above.
            VStack(alignment: .leading, spacing: 4) {
                Text("Trial-nyckel")
                SecureField("Nyckeln du fick av Carl", text: $trialKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: trialKey) { _, value in
                        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            UserDefaults.standard.removeObject(forKey: SyncSettings.trialKeyDefaultsKey)
                        } else {
                            UserDefaults.standard.set(trimmed, forKey: SyncSettings.trialKeyDefaultsKey)
                        }
                    }
            }
            // The typed address and the used address are different things until the next launch.
            // Without this line the two are indistinguishable on a phone, which is exactly how a
            // correctly-typed address reads as "cannot reach the server".
            LabeledContent("Kör mot", value: Bootstrap.activeBaseURL?.absoluteString ?? "—")
            Text("Tomt = den inbyggda servern och nyckeln. Fyll i bara för att köra mot en annan server. Kräver omstart av appen.")
                .font(.caption2)
                .foregroundStyle(Theme.secondary)
            LabeledContent("I kö för uppladdning", value: "\((try? ledger.pendingPushCount()) ?? -1)")
            LabeledContent("Överhoppade händelser", value: "\(ledger.state.skipped.count)")
            LabeledContent("Oläsbara rader", value: "\(ledger.rejected.count)")
            Button("Bygg om projektioner från loggen", systemImage: "arrow.clockwise") {
                perform { try ledger.rebuild() }
            }
            Button("Lägg till testdata", systemImage: "plus") {
                perform { try SeedData.insert(into: ledger) }
            }
            NavigationLink {
                SwishFormatTester(number: profile.swishNumber)
            } label: {
                Label("Testa Swish-format", systemImage: "link")
            }
            Button("Stäng av utvecklarläge", role: .destructive) {
                devToolsVisible = false
            }
        }
    }
    #endif

    // MARK: - Actions

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

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            failure = nil
        } catch {
            failure = String(describing: error)
        }
    }
}

/// The Apple-Settings row glyph: a white symbol on a solid rounded square. Every row in Jag leads
/// with one, which is most of what makes the screen read as Settings rather than as a form.
private struct SettingsIcon: View {
    let systemImage: String
    let fill: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(fill)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }
}

#if DEBUG
/// Every Swish URL shape we know of, against one krona, so the phone can settle which one works.
///
/// The `swish://payment?data=` shape is undocumented and a real phone answered *"länken som
/// användes för att öppna appen har ett felaktigt format"*. The universal link is what Swish's own
/// site hands out. Neither can be judged from here: the simulator has no Swish app, so
/// `canOpenURL` is always false and `openURL` always fails there.
///
/// So this exists to make the device loop cheap. Without it, every guess costs a build, a deploy
/// to the phone and a message back. With it, one session tries all of them and the answer is which
/// row opened Swish with 1,00 kr in it. Debug only — it is a diagnostic, not a feature.
private struct SwishFormatTester: View {
    @State var number: String
    @Environment(\.openURL) private var openURL
    @State private var lastResult: String?

    /// One krona, so an accidental tap-through in Swish is a rounding error and not a problem.
    private var amount: Money { Money(amountMinor: 100, currency: .sek) }
    private let message = "Slice test"

    private var candidates: [(name: String, url: URL)] {
        var found: [(String, URL)] = []
        if let link = PaymentLinkBuilder.swish(payee: number, amount: amount, message: message) {
            found.append(("Universell länk (app.swish.nu)", link.url))
        }
        if let link = PaymentLinkBuilder.swishAppSwitch(
            payee: number, amount: amount, message: message,
            callback: URL(string: "kvitta://payment-return")
        ) {
            found.append(("swish://payment?data= med callback", link.url))
        }
        if let link = PaymentLinkBuilder.swishAppSwitch(
            payee: number, amount: amount, message: message, callback: nil
        ) {
            found.append(("swish://payment?data= utan callback", link.url))
        }
        if let bare = URL(string: "swish://") {
            found.append(("Bara swish:// (öppnar appen tom)", bare))
        }
        return found
    }

    var body: some View {
        Form {
            Section {
                TextField("", text: $number, prompt: Text("07XX XXX XX XX").placeholderStyle())
                    .keyboardType(.phonePad)
                LabeledContent("Normaliserat", value: SwishNumber.normalised(number) ?? "—")
            } header: {
                Text("Nummer")
            } footer: {
                Text("Skickar 1,00 kr. Titta på skärmen i Swish och avbryt — genomför inte betalningen.")
            }

            ForEach(candidates, id: \.name) { candidate in
                Section {
                    Button("Öppna") {
                        openURL(candidate.url) { opened in
                            lastResult = opened
                                ? "Öppnade: \(candidate.name)"
                                : "Ingen app tog emot: \(candidate.name)"
                        }
                    }
                    Text(candidate.url.absoluteString)
                        .font(.caption.monospaced())
                        .foregroundStyle(Theme.secondary)
                        .textSelection(.enabled)
                } header: {
                    Text(candidate.name)
                }
            }

            if let lastResult {
                Section {
                    Text(lastResult).font(.footnote).foregroundStyle(Theme.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AmbientBackground())
        .navigationTitle("Testa Swish-format")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

/// The events the server refused, and why — reachable from the backup section rather than
/// dumped on the front of the screen.
private struct RejectedPushList: View {
    let ledger: LedgerStore

    var body: some View {
        List(Array(ledger.rejectedPushes.enumerated()), id: \.offset) { _, rejected in
            VStack(alignment: .leading, spacing: 4) {
                Text(describe(rejected.code))
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                Text(rejected.event.type)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(AmbientBackground())
        .navigationTitle("Kunde inte sparas")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The server's codes are stable strings meant to be shown to a person, once translated.
    private func describe(_ code: String) -> String {
        switch code {
        case "money_invariant_violated": return String(localized: "Beloppen gick inte ihop.")
        case "not_a_member": return String(localized: "Du är inte längre med i gruppen.")
        case "unknown_member": return String(localized: "Någon i utgiften finns inte i gruppen.")
        case "currency_mismatch": return String(localized: "Fel valuta för gruppen.")
        default: return String(localized: "Servern kunde inte ta emot den här posten.")
        }
    }
}

// squareThumbnail moved to UserProfile.swift — group photos need it too.
