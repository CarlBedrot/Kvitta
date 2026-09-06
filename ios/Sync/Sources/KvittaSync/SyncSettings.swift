import Foundation

/// The feature flag.
///
/// Off by default, and deliberately checked on every call rather than captured once: flipping it
/// in the Jag tab has to take effect without relaunching, and turning it *off* has to stop an
/// in-progress loop from starting another round.
public struct SyncSettings: Sendable {
    private let isEnabledProvider: @Sendable () -> Bool

    public init(isEnabled: @escaping @Sendable () -> Bool) {
        self.isEnabledProvider = isEnabled
    }

    public var isEnabled: Bool { isEnabledProvider() }

    /// Reads `UserDefaults`, so the toggle survives a relaunch.
    public static let standard = SyncSettings {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    public static let enabled = SyncSettings { true }
    public static let disabled = SyncSettings { false }

    public static let defaultsKey = "se.kvitta.syncEnabled"

    /// Where the Jag tab keeps the trial key a hosted server asks for on dev sign-in. Read once
    /// at launch by the app's bootstrap, alongside the server address. Not the Keychain: it is a
    /// shared gate for a friend group, not a personal credential, and it lives next to the
    /// address it belongs to so the two are set and cleared together.
    public static let trialKeyDefaultsKey = "se.kvitta.trialKey"

    public static func setEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: defaultsKey)
    }
}
