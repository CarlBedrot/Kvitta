import SwiftUI
import KvittaCore
import KvittaStorage

@main
struct KvittaApp: App {
    @State private var startup = Bootstrap.run()

    var body: some Scene {
        WindowGroup {
            // A switch over an enum returning concrete views, not AnyView (CLAUDE.md) — the
            // WindowGroup body is already a @ViewBuilder, so this costs nothing.
            switch startup {
            case .ready(let ledger):
                RootView(ledger: ledger, userId: DeviceIdentity.userId)
            case .failed(let message):
                StartupFailureView(message: message)
            }
        }
    }
}

enum Startup {
    case ready(LedgerStore)
    case failed(String)
}

@MainActor
enum Bootstrap {
    /// Opens the database and folds the whole log into a projection before the first frame.
    ///
    /// This is the same `rebuild()` the debug menu calls. Making launch and recovery one code
    /// path means the recovery path is exercised on every single launch rather than never.
    /// A heavy group costs about 20 ms here, which is why there is no loading state anywhere.
    static func run() -> Startup {
        do {
            let ledger = LedgerStore(
                store: try EventStore.onDisk(at: databaseURL),
                authorId: DeviceIdentity.userId
            )
            try ledger.rebuild()
            return .ready(ledger)
        } catch {
            // Deliberately not a silent fallback to an in-memory store: that would look like a
            // working app that quietly forgets everything, which is worse than saying so.
            return .failed(String(describing: error))
        }
    }

    static var databaseURL: URL {
        URL.applicationSupportDirectory.appending(path: "Kvitta/kvitta.sqlite")
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
