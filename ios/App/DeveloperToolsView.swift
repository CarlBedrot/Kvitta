#if DEBUG
import SwiftUI
import KvittaCore
import KvittaStorage
import KvittaSync

/// Mer → Utvecklarverktyg, only once unlocked (seven taps on "Om appen" — `MerView`). Debug-only
/// counters and switches that used to sit in front of everyone on this screen; moved behind a
/// row instead of removed, because every build that reaches a phone today *is* a debug build.
struct DeveloperToolsView: View {
    let ledger: LedgerStore
    let sync: SyncEngine
    let profile: UserProfile

    @Environment(\.dismiss) private var dismiss
    @AppStorage("se.kvitta.devToolsVisible") private var devToolsVisible = false
    @State private var serverAddress = UserDefaults.standard.string(forKey: "se.kvitta.syncBaseURL") ?? ""
    @State private var trialKey = UserDefaults.standard.string(forKey: SyncSettings.trialKeyDefaultsKey) ?? ""
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 0) {
            Steven.NavTitleBar(title: "Utvecklarverktyg", leading: .back { dismiss() })
            Form {
                Section {
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
                    // For the sideloaded-to-a-friend's-phone trial: their phone must reach the
                    // dev backend on your Mac's LAN address, not its own localhost. Read at
                    // launch (Bootstrap.syncConfiguration), hence the restart note below.
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
                    // The hosted trial server keeps the dev sign-in on behind a shared key
                    // (Auth:TrialKey on the server). Saved on every keystroke, same reason as
                    // the address above: the URL keyboard's return key is easy to miss.
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
                    if let failure {
                        Text(failure).font(.footnote).foregroundStyle(Theme.clay)
                    }
                    Button("Stäng av utvecklarläge", role: .destructive) {
                        devToolsVisible = false
                        dismiss()
                    }
                } header: {
                    Text("Utvecklarverktyg")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(StevenColor.screen)
        .navigationBarHidden(true)
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
#endif
