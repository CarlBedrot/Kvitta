import SwiftUI
import KvittaCore
import KvittaStorage
import KvittaSync

/// Mer (05, 06): who you are, and a list of everything else that is not a group. Replaces the old
/// Jag/profile screen (#157) — profile editing itself moved to `MinaDetaljerView` and
/// `ProfileEditorView`, so this file is now just the list and its unlock ritual for the developer
/// tools, exactly as before.
struct MerView: View {
    let ledger: LedgerStore
    let sync: SyncEngine
    @Bindable var profile: UserProfile
    let session: SessionModel
    let reminders: ReminderScheduler
    let rates: RateStore
    let userId: UserID

    @AppStorage(AppAppearance.defaultsKey) private var appearance = AppAppearance.system
    #if DEBUG
    // Compile-time gating alone stopped meaning "developers only" the day the app reached real
    // phones: every build anyone actually runs is a Debug build (Xcode sideload, simulator) and
    // will be until TestFlight exists. So even in Debug the row hides until deliberately asked
    // for — seven taps on "Om appen", the same ritual every phone OS taught people.
    @AppStorage("se.kvitta.devToolsVisible") private var devToolsVisible = false
    @State private var versionTaps = 0
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    Steven.Hairline(color: StevenColor.rowSeparator)
                    rows
                }
                .background(StevenColor.surface)
            }
            .background(StevenColor.surface)
            .contentMargins(.bottom, 32, for: .scrollContent)
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Avatar(name: profile.nameOrDefault, photo: profile.avatarData, size: StevenMetric.avatarHero)
            Text(verbatim: profile.nameOrDefault)
                .stevenFont(.cardTitle)
                .foregroundStyle(StevenColor.ink)
            Text(verbatim: profile.paymentPhone?.international ?? "")
                .stevenFont(.rowTitle)
                .foregroundStyle(StevenColor.muted)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var rows: some View {
        NavigationLink {
            MinaDetaljerView(profile: profile, session: session)
        } label: {
            Steven.ListRow(title: "Mina detaljer") {
                Avatar(name: profile.nameOrDefault, photo: profile.avatarData, size: 28)
            }
        }
        .buttonStyle(Steven.RowButtonStyle())

        Menu {
            Picker("Utseende", selection: $appearance) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        } label: {
            Steven.ListRow(icon: "circle.lefthalf.filled", title: "Utseende", trailing: .value(appearance.valueText))
        }

        Steven.ListRow(icon: "bell", title: "Påminn mig om skulder", trailing: .toggle(Binding(
            get: { reminders.isEnabled },
            set: { on in Task { await reminders.setEnabled(on, ledger: ledger, userId: userId) } }
        )))

        NavigationLink {
            HelpCenterView()
        } label: {
            Steven.ListRow(icon: "questionmark.square", title: "Hjälpcenter")
        }
        .buttonStyle(Steven.RowButtonStyle())

        aboutRow

        ShareLink(item: String(localized: "Jag använder Slice för att dela utgifter med vänner. Fråga mig om du vill vara med!")) {
            Steven.ListRow(icon: "square.and.arrow.up", title: "Dela till en vän")
        }
        .buttonStyle(Steven.RowButtonStyle())

        ShareLink(item: DiagnosticReport.text(
            ledger: ledger, sync: sync, rates: rates, signedIn: session.isSignedIn
        )) {
            Steven.ListRow(icon: "ladybug", title: "Dela felrapport")
        }
        .buttonStyle(Steven.RowButtonStyle())

        NavigationLink {
            AccountStatusView(ledger: ledger, session: session, profile: profile)
        } label: {
            Steven.ListRow(icon: "person.crop.circle", title: "Konto")
        }
        .buttonStyle(Steven.RowButtonStyle())

        #if DEBUG
        if devToolsVisible {
            NavigationLink {
                DeveloperToolsView(ledger: ledger, sync: sync, profile: profile)
            } label: {
                Steven.ListRow(icon: "wrench.and.screwdriver", title: "Utvecklarverktyg", showsSeparator: false)
            }
            .buttonStyle(Steven.RowButtonStyle())
        }
        #endif
    }

    /// Version straight from the bundle, and the door into the developer section: seven taps,
    /// counted per visit to this screen — no timer, no feedback until the row simply appears.
    private var aboutRow: some View {
        Steven.ListRow(icon: "info.circle", title: "Om appen", trailing: .value(versionText, chevron: false))
        #if DEBUG
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

    private var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }
}

/// The events the server refused, and why — reachable from `AccountStatusView` rather than
/// dumped on the front of the screen.
struct RejectedPushList: View {
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
        .background(StevenColor.screen)
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

#if DEBUG
/// Every Swish URL shape we know of, against one krona, so the phone can settle which one works.
///
/// The `swish://payment?data=` shape is undocumented and a real phone answered *"länken som
/// används för att öppna appen har ett felaktigt format"*. The universal link is what Swish's own
/// site hands out. Neither can be judged from here: the simulator has no Swish app, so
/// `canOpenURL` is always false and `openURL` always fails there.
///
/// So this exists to make the device loop cheap. Without it, every guess costs a build, a deploy
/// to the phone and a message back. With it, one session tries all of them and the answer is which
/// row opened Swish with 1,00 kr in it. Debug only — it is a diagnostic, not a feature.
struct SwishFormatTester: View {
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
        .background(StevenColor.screen)
        .navigationTitle("Testa Swish-format")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
