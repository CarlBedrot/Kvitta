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

    @State private var photoItem: PhotosPickerItem?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                accountSection
                backupSection
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

    private var profileSection: some View {
        Section {
            HStack(spacing: 16) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        Avatar(name: profile.nameOrDefault, photo: profile.avatarData, size: 64)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Theme.clayBright, in: .circle)
                            .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Ditt namn", text: $profile.displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Visas som du i nya grupper.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }
            }
            .padding(.vertical, 6)

            if profile.avatarData != nil {
                Button("Ta bort bild", role: .destructive) {
                    profile.avatarData = nil
                    photoItem = nil
                }
            }
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
                    Text("Inloggad")
                    Spacer()
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.sage)
                }

                Button("Logga ut", role: .destructive) {
                    Task { await session.signOut() }
                }
            } else {
                Button {
                    Task { await session.signIn(displayName: profile.displayName) }
                } label: {
                    HStack {
                        Text("Logga in")
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
                 : "Du behöver inget konto för att använda Kvitta. Ett konto gör bara att dina utgifter finns kvar om telefonen försvinner.")
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
                Text("Status")
                Spacer()
                Text(backupStatus)
                    .foregroundStyle(backupIsHealthy ? Theme.secondary : Theme.clay)
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
        switch sync.status {
        case .disabled: return "Bara på den här telefonen"
        case .idle: return sync.lastSyncedAt == nil ? "Klar" : "Allt är sparat"
        case .syncing: return "Sparar…"
        case .offline: return "Väntar på anslutning"
        case .blocked(let message): return message
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
            LabeledContent("I kö för uppladdning", value: "\((try? ledger.pendingPushCount()) ?? -1)")
            LabeledContent("Överhoppade händelser", value: "\(ledger.state.skipped.count)")
            LabeledContent("Olästa rader", value: "\(ledger.rejected.count)")
            Button("Bygg om projektioner från loggen", systemImage: "arrow.clockwise") {
                perform { try ledger.rebuild() }
            }
            Button("Lägg till testdata", systemImage: "plus") {
                perform { try SeedData.insert(into: ledger) }
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
        case "money_invariant_violated": return "Beloppen gick inte ihop."
        case "not_a_member": return "Du är inte längre med i gruppen."
        case "unknown_member": return "Någon i utgiften finns inte i gruppen."
        case "currency_mismatch": return "Fel valuta för gruppen."
        default: return "Servern kunde inte ta emot den här posten."
        }
    }
}

private extension UIImage {
    /// Centre-cropped to a square and scaled down, so avatars are cheap to store and to draw.
    func squareThumbnail(side: CGFloat) -> UIImage? {
        let shortest = min(size.width, size.height)
        let crop = CGRect(
            x: (size.width - shortest) / 2,
            y: (size.height - shortest) / 2,
            width: shortest,
            height: shortest
        )
        guard let cropped = cgImage?.cropping(to: crop) else { return nil }

        let target = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: target).image { _ in
            UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
                .draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
