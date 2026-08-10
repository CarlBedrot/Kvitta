import Foundation
import Sentry

/// Crash reporting for the app target.
///
/// Off unless `SentryDSN` in the Info.plist has a value, which is the whole of the switch — a
/// fresh clone builds and runs with no reporting and no configuration step, the same way it builds
/// with no backend. The DSN lives in `project.yml` rather than a secret store on purpose: a client
/// DSN ships inside every copy of an app anyway and can only write, never read.
///
/// This type exists only in `ios/App`. `KvittaCore` has zero dependencies and must keep them
/// (CLAUDE.md), and the two packages either side of it have exactly one apiece; a reporter belongs
/// at the edge that owns the process, not inside the logic it reports on.
enum Observability {

    /// What is deliberately never sent, and why each is a decision rather than a default.
    ///
    /// - A **screenshot** of this app is the friend group's money on screen: every name, every
    ///   amount, every debt. Sentry defaults to off; it is set explicitly because the option
    ///   exists one autocomplete away from a debugging session.
    /// - The **view hierarchy** is the same picture in text form, including the label strings.
    /// - **PII** — device name, IP, Apple account. Not ours to hand to a third party, and the
    ///   server's own logging policy already says ids instead of names.
    ///
    /// What is kept: group and member ids, screen names, sync failure codes. Those are what the
    /// existing "Dela felrapport" screen already shares, and they are what makes a crash report
    /// worth having at all.
    static func start(bundle: Bundle = .main) {
        guard let dsn = dsn(in: bundle) else { return }

        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = isDebugBuild ? "debug" : "release"
            options.releaseName = releaseName(in: bundle)

            options.sendDefaultPii = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false

            // A friend group's app on a free plan. Performance traces of every screen transition
            // would spend the month's quota on numbers nobody reads; crashes are the point.
            options.tracesSampleRate = 0

            options.beforeSend = { event in scrub(event) }
        }
    }

    /// Non-empty DSN, or nil. Whitespace counts as empty, because an accidentally blanked-out
    /// plist value should behave like the off state rather than like a malformed DSN.
    static func dsn(in bundle: Bundle) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: "SentryDSN") as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The last thing that touches an event before it leaves the phone.
    ///
    /// Mirrors `SentryScrubbing` on the server, and is a pure function for the same reason: it can
    /// be asserted without a DSN, a network, or a started SDK.
    static func scrub(_ event: Event) -> Event? {
        // Set by the SDK from the device even with PII off in some configurations. Nulling it here
        // means there is one answer rather than a version-dependent one.
        event.user?.ipAddress = nil
        event.user?.email = nil
        event.user?.username = nil

        event.context?["device"]?["name"] = nil

        return event
    }

    private static func releaseName(in bundle: Bundle) -> String? {
        guard
            let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        else {
            return nil
        }

        // Matches the identifier the server's MinimumClientBuild gate speaks in, so a crash and a
        // 426 can be traced to the same build without a lookup table.
        return "se.kvitta.app@\(version)+\(build)"
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
