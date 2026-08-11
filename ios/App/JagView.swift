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
/// debug builds, and what is left says one thing: is everything saved.
struct JagView: View {
    let ledger: LedgerStore
    let sync: SyncEngine
    @Bindable var profile: UserProfile
    let session: SessionModel
    let invites: InviteModel
    let reminders: ReminderScheduler
    let rates: RateStore
    let userId: UserID

    @State private var photoItem: PhotosPickerItem?
    @State private var failure: String?
    @State private var inviteCode = ""
    #if DEBUG
    @State private var serverAddress = UserDefaults.standard.string(forKey: "se.kvitta.syncBaseURL") ?? ""
    #endif

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                accountSection
                joinSection
                remindersSection
                backupSection
                aboutSection
                helpSection
                #if DEBUG
                developerSection
                #endif
                if let failure {
                    Section {
                        Text(failure).font(.footnote).foregroundStyle(Theme.clay)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmbientBackground())
            .navigationTitle("Jag")
            .task(id: photoItem) { await loadPhoto() }
        }
    }

    // MARK: - Profile

    @ViewBuilder
    private var profileSection: some View {
        Section {
            // The large profile header, Apple-Settings style: the person first, everything else
            // in grouped cards below.
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

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Ditt namn", text: $profile.displayName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Visas som du i nya grupper.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }
            }
            .padding(.vertical, 8)

            if profile.avatarData != nil {
                Button("Ta bort bild", role: .destructive) {
                    profile.avatarData = nil
                    photoItem = nil
                }
            }
        }

        swishNumberSection
    }

    /// The number people Swish you on.
    ///
    /// It stays on this phone and is never written to a group log — an event is immutable, so a
    /// phone number in one would reach every member forever with no way to withdraw it
    /// (CLAUDE.md). What crosses to the other person is a link you send them, from the settle-up
    /// screen, with the amount already in it.
    @ViewBuilder
    private var swishNumberSection: some View {
        Section {
            HStack {
                SettingsIcon(systemImage: "creditcard.fill", fill: Color(hex: 0xEE4A9B))
                Text("Swish-nummer")
                Spacer()
                TextField("07XX XXX XX XX", text: $profile.swishNumber)
                    .keyboardType(.phonePad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Theme.ink)
            }

            if !profile.swishNumber.isEmpty && profile.swishNumberForPayment == nil {
                Text("Det där ser inte ut som ett nummer Swish känner igen.")
                    .font(.footnote)
                    .foregroundStyle(Theme.clay)
            }
        } footer: {
            Text("Delas med medlemmarna i dina grupper så att de kan swisha rätt nummer. Tar du bort det slutar det delas. Utan konto sparas det bara på den här telefonen.")
        }
    }

    // MARK: - Account

    /// Signing in is optional and the copy says so.
    ///
    /// The app works completely without an account — that is the premise, not a limitation — so
    /// this section offers one benefit and never nags. It is also the only place the difference
    /// between "on this phone" and "safe if you lose this phone" is stated plainly.
    @ViewBuilder
    private var accountSection: some View {
        Section {
            if session.isSignedIn {
                HStack {
                    SettingsIcon(systemImage: "person.crop.circle.fill", fill: Theme.positive)
                    Text("Inloggad")
                    Spacer()
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.positive)
                }

                Button("Logga ut", role: .destructive) {
                    Task { await session.signOut() }
                }
            } else {
                Button {
                    Task { await session.signIn(displayName: profile.displayName) }
                } label: {
                    HStack {
                        SettingsIcon(systemImage: "person.crop.circle.fill", fill: Theme.accent)
                        Text("Logga in").foregroundStyle(Theme.ink)
                        Spacer()
                        if session.isWorking { ProgressView() }
                    }
                }
                .disabled(session.isWorking)
            }

            if let failure = session.failure {
                Text(failure).font(.footnote).foregroundStyle(Theme.clay)
            }
        } header: {
            Text("Konto")
        } footer: {
            Text(session.isSignedIn
                 ? "Nya utgifter sparas hos servern så att de överlever om du byter telefon."
                 : "Du behöver inget konto för att använda Slice. Ett konto gör bara att dina utgifter finns kvar om telefonen försvinner.")
        }
    }

    // MARK: - Joining

    /// Accepting an invite by pasting the code.
    ///
    /// Tapping the link is the normal path and needs no UI at all. This exists because links get
    /// mangled — forwarded through chat apps, screenshotted, read out loud — and a group you
    /// cannot join because a URL lost its scheme is a bad afternoon. It takes the bare token too.
    @ViewBuilder
    private var joinSection: some View {
        Section {
            HStack {
                SettingsIcon(systemImage: "envelope.fill", fill: Theme.positive)
                TextField("Klistra in inbjudningskod", text: $inviteCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Button {
                Task {
                    await invites.accept(rawCode: inviteCode)
                    if case .joined = invites.outcome { inviteCode = "" }
                }
            } label: {
                HStack {
                    Text("Gå med i grupp")
                    Spacer()
                    if invites.isWorking { ProgressView() }
                }
            }
            .disabled(inviteCode.isEmpty || invites.isWorking)

            switch invites.outcome {
            case .joined:
                Text("Du är med i gruppen.").font(.footnote).foregroundStyle(Theme.sage)
            case .failed(let reason):
                Text(reason).font(.footnote).foregroundStyle(Theme.clay)
            case nil:
                EmptyView()
            }
        } header: {
            Text("Inbjudan")
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
        Section {
            HStack {
                SettingsIcon(systemImage: "bell.badge.fill", fill: Theme.accent)
                Toggle("Påminn mig om skulder", isOn: Binding(
                    get: { reminders.isEnabled },
                    set: { on in Task { await reminders.setEnabled(on, ledger: ledger, userId: userId) } }
                ))
            }

            if reminders.wasDenied {
                Text("Notiser är avstängda för Slice i Inställningar.")
                    .font(.footnote)
                    .foregroundStyle(Theme.clay)
            }
        } footer: {
            Text("En påminnelse i veckan, bara när du är skyldig någon pengar. Aldrig om någon är skyldig dig.")
        }
    }

    // MARK: - Backup

    /// Deliberately framed as "is my data safe", not as "sync". A person does not want a switch
    /// labelled sync; they want to know nothing is lost. The switch itself is a developer control
    /// until Milestone 4 makes sync something a user can meaningfully own.
    @ViewBuilder
    private var backupSection: some View {
        Section {
            HStack {
                SettingsIcon(
                    systemImage: "externaldrive.fill",
                    fill: backupIsHealthy ? Color(hex: 0x8E8A82) : Theme.negative
                )
                Text("Status")
                Spacer()
                Text(backupStatus)
                    .foregroundStyle(backupIsHealthy ? Theme.secondary : Theme.negative)
            }

            if !ledger.rejectedPushes.isEmpty {
                // Design doc §7: rejected events are surfaced, never dropped.
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
        } header: {
            Text("Säkerhetskopiering")
        } footer: {
            Text(sync.isEnabled
                 ? "Dina utgifter finns alltid på telefonen. Kopian hos servern gör att de överlever om du byter telefon."
                 : "Dina utgifter finns på den här telefonen. Säkerhetskopiering till servern är inte påslagen än.")
        }
    }

    private var backupIsHealthy: Bool {
        switch sync.status {
        case .blocked: return false
        default: return ledger.rejectedPushes.isEmpty
        }
    }

    /// Plain language. "Offline" is a normal state for this app, not a problem worth a red badge.
    private var backupStatus: String {
        // `String(localized:)` on every branch: a plain literal returned from a `String`
        // property never passes through the catalog, which is how this row stayed Swedish on
        // an English phone while everything around it translated.
        switch sync.status {
        case .disabled: return String(localized: "Bara på den här telefonen")
        case .idle:
            return sync.lastSyncedAt == nil
                ? String(localized: "Klar")
                : String(localized: "Allt är sparat")
        case .syncing: return String(localized: "Sparar…")
        case .offline: return String(localized: "Väntar på anslutning")
        case .blocked(let message): return message
        }
    }

    // MARK: - About

    /// Version and build straight from the bundle — no hand-maintained copy to go stale.
    private var aboutSection: some View {
        Section("Om Slice") {
            HStack {
                SettingsIcon(systemImage: "info.circle.fill", fill: Color(hex: 0xA5A099))
                LabeledContent(
                    "Version",
                    value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))"
                )
            }
        }
    }

    // MARK: - Help

    /// The escape hatch for "something looks wrong on my phone": a shareable state report.
    /// Not debug-gated — the whole point is that a friend on a release build can send one.
    private var helpSection: some View {
        Section {
            ShareLink(item: DiagnosticReport.text(
                ledger: ledger, sync: sync, rates: rates, signedIn: session.isSignedIn
            )) {
                HStack {
                    SettingsIcon(systemImage: "ladybug.fill", fill: Color(hex: 0x6E7F5C))
                    Text("Dela felrapport").foregroundStyle(Theme.ink)
                }
            }
        } footer: {
            Text("En textrapport om appens tillstånd — inga namn, belopp eller nummer. Skicka den till den som hjälper dig.")
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
                TextField("http://192.168.x.x:5142", text: $serverAddress)
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
            // The typed address and the used address are different things until the next launch.
            // Without this line the two are indistinguishable on a phone, which is exactly how a
            // correctly-typed address reads as "cannot reach the server".
            LabeledContent("Kör mot", value: Bootstrap.activeBaseURL?.absoluteString ?? "—")
            Text("Tom = localhost. Kräver omstart av appen.")
                .font(.caption2)
                .foregroundStyle(Theme.tertiary)
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
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(fill, in: .rect(cornerRadius: 7))
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
                TextField("07XX XXX XX XX", text: $number)
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
