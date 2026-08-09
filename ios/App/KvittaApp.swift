import SwiftUI
import KvittaCore
import KvittaStorage
import KvittaSync

@main
struct KvittaApp: App {
    @State private var profile: UserProfile
    @State private var startup: Startup
    @State private var reminders = ReminderScheduler()
    @State private var rates = RateStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Built here rather than as inline defaults because the object graph has an order:
        // the invite flow needs the profile to know what name to join a group under.
        let profile = UserProfile()
        _profile = State(initialValue: profile)
        _startup = State(initialValue: Bootstrap.run(profile: profile))
    }

    var body: some Scene {
        WindowGroup {
            // A switch over an enum returning concrete views, not AnyView (CLAUDE.md) — the
            // WindowGroup body is already a @ViewBuilder, so this costs nothing.
            switch startup {
            case .ready(let ledger, let sync, let session, let invites, let profiles, let photos):
                RootView(
                    ledger: ledger,
                    userId: session.userId ?? DeviceIdentity.userId,
                    sync: sync,
                    profile: profile,
                    session: session,
                    invites: invites,
                    reminders: reminders,
                    rates: rates,
                    profiles: profiles,
                    photos: photos
                )
                // The palette is light-only by design (`Theme`), and the plist says so too. This
                // is the SwiftUI half of the same statement, so Previews and any future scene
                // agree with the shipped app instead of quietly rendering white on cream.
                .preferredColorScheme(.light)
                .task {
                    await session.restore()
                    // Recomputed at launch, so a debt settled on another device does not
                    // leave a stale reminder queued here.
                    await reminders.reschedule(ledger: ledger, userId: session.userId ?? DeviceIdentity.userId)
                }
                .onOpenURL { url in
                    // slice://invite/<token> (kvitta:// still accepted). A custom scheme rather than a universal link,
                    // because an https link needs an apple-app-site-association file on a host
                    // that does not exist until the deploy. Adding universal links later is
                    // additive — the token and the endpoint do not change.
                    guard let token = InviteModel.token(in: url.absoluteString) else { return }
                    Task { await invites.accept(token: token) }
                }
                .onChange(of: scenePhase) { _, phase in
                    // Foreground pull is the guarantee (design doc §6). Everything else —
                    // debounced post-save pushes, and APNs in M5 — only makes it sooner.
                    guard phase == .active else { return }
                    Task { await sync.syncAll() }
                    // The day's ECB fixing, refreshed at most once per date. Failure is silence:
                    // conversion is a convenience on top of exact numbers, never a dependency.
                    Task { await rates.refresh() }
                    // Your Swish number up to the server, if it changed. Same silence: the
                    // type-it-yourself flow is the working fallback.
                    Task { await profiles.push(profile) }
                }
            case .failed(let message):
                StartupFailureView(message: message).preferredColorScheme(.light)
            }
        }
    }
}

enum Startup {
    case ready(LedgerStore, SyncEngine, SessionModel, InviteModel, ProfileSyncer, GroupPhotoSyncer)
    case failed(String)
}

@MainActor
enum Bootstrap {
    /// Opens the database and folds the whole log into a projection before the first frame.
    ///
    /// This is the same `rebuild()` the debug menu calls. Making launch and recovery one code
    /// path means the recovery path is exercised on every single launch rather than never.
    /// A heavy group costs about 20 ms here, which is why there is no loading state anywhere.
    ///
    /// Measured 2026-08-09 (Release, iPhone 17 Pro simulator), because the app looks blank for
    /// a couple of seconds on open and this function is the obvious suspect: it is not. Opening
    /// the database plus the whole replay is 66–265 ms — the replay itself 9–40 ms — and it is
    /// the same with four seeded groups as with an empty ledger. The rest of the wait is UIKit
    /// and SwiftUI standing the scene up before any of our code is asked for a view, which is
    /// why no spinner can fill it: nothing we can draw exists yet. The launch screen is the
    /// only surface alive in that window, so that is where the branding goes (`UILaunchScreen`
    /// in project.yml). Do not add a loading state here expecting it to help.
    static func run(profile: UserProfile) -> Startup {
        do {
            let ledger = LedgerStore(
                store: try EventStore.onDisk(at: databaseURL),
                authorId: DeviceIdentity.userId
            )
            try ledger.rebuild()

            // Constructed unconditionally, but inert until the flag is on. Note that nothing
            // about opening the database or replaying the log depends on any of it — if every
            // line below were deleted the app above this one would behave identically.
            let configuration = syncConfiguration
            let authClient = HTTPAuthClient(configuration: configuration)
            let tokens = AuthTokenProvider(store: KeychainTokenStore(), refresher: authClient)

            let sync = SyncEngine(
                ledger: ledger,
                transport: HTTPSyncTransport(configuration: configuration, tokens: tokens),
                userId: DeviceIdentity.userId
            )

            let session = SessionModel(
                tokens: tokens,
                // The real Sign in with Apple provider is written and compiles, but cannot run
                // without the com.apple.developer.applesignin entitlement — which needs a paid
                // Apple Developer team. Swap this line and add the entitlement to switch over.
                provider: DeveloperSignInProvider(client: authClient, userId: DeviceIdentity.userId),
                ledger: ledger,
                sync: sync
            )

            let transport = HTTPSyncTransport(configuration: configuration, tokens: tokens)
            let invites = InviteModel(
                transport: transport,
                sync: sync,
                session: session,
                profile: profile
            )

            let profiles = ProfileSyncer(transport: transport, session: session)
            let photos = GroupPhotoSyncer(transport: transport, session: session)

            return .ready(ledger, sync, session, invites, profiles, photos)
        } catch {
            // Deliberately not a silent fallback to an in-memory store: that would look like a
            // working app that quietly forgets everything, which is worse than saying so.
            return .failed(String(describing: error))
        }
    }

    static var databaseURL: URL {
        URL.applicationSupportDirectory.appending(path: "Kvitta/kvitta.sqlite")
    }

    /// Points at the local server by default. A real host lands with the deploy in M6.
    static var syncConfiguration: SyncConfiguration {
        let stored = UserDefaults.standard.string(forKey: "se.kvitta.syncBaseURL")
        let url = stored.flatMap(URL.init(string:)) ?? URL(string: "http://localhost:5142")!
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return SyncConfiguration(baseURL: url, buildNumber: Int(build ?? "1") ?? 1)
    }
}

/// The local user's identity, until Sign in with Apple lands in Milestone 4.
///
/// Only ever the `authorId` stamped on events — never a `MemberID`. Expenses reference members,
/// and members are only optionally linked to users (design doc §5), which is what lets the app
/// split with people who never sign up.
enum DeviceIdentity {
    private static let key = "se.kvitta.localUserId"

    static var userId: UserID {
        if let stored = UserDefaults.standard.string(forKey: key),
           let existing = UserID(uuidString: stored) {
            return existing
        }
        let fresh = UserID()
        UserDefaults.standard.set(fresh.rawValue.uuidString, forKey: key)
        return fresh
    }
}

struct StartupFailureView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Kunde inte öppna databasen", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
    }
}
