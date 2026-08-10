import Foundation
import KvittaCore
import KvittaStorage

/// What you have not looked at yet, on this phone.
///
/// Deliberately not an event. "Carl has read this" would be copied to every member's device
/// forever and could never be taken back — events are immutable — which is a great deal of
/// permanence for a fact that is nobody else's business. Same reasoning as `PayeeDirectory` and
/// the Swish number.
///
/// So read state is one integer in `UserDefaults`: the `receivedAt` of the newest event this
/// device had heard about the last time the feed was on screen. Everything that arrived after it,
/// and that somebody else wrote, is unread. That needs no network and no account, which matters —
/// the app without an account is the offline app and must stay fully functional.
@MainActor
@Observable
final class UnreadStore {
    private let defaults: UserDefaults
    private let key = "se.kvitta.activity.lastSeenReceivedAt"

    /// The unread entity ids, recomputed rather than stored. A cached count would be a second copy
    /// of a truth the log already holds, free to drift from it — the same argument that keeps
    /// projections out of the database.
    private(set) var unread: Set<UUID> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var count: Int { unread.count }

    func isUnread(_ entityId: UUID) -> Bool { unread.contains(entityId) }

    /// Recomputes the badge. Cheap: only events newer than the mark are decoded.
    ///
    /// Failure is silent by design. An unreadable log costs a badge, and a badge is not worth an
    /// error in front of somebody trying to split a restaurant bill.
    func refresh(from ledger: LedgerStore) {
        // First run on this device: adopt whatever is already there as seen, rather than
        // announcing it. Signing in pulls a group's entire history at once and stamps all of it
        // as received now, so the honest-looking alternative — "you have not looked at any of
        // this" — opens the app on a badge of two hundred for a ledger the user has been reading
        // on another phone for months. Unread means "since you last looked", and someone who has
        // never looked has nothing to catch up on.
        if !hasMark {
            defaults.set(pendingMark(from: ledger), forKey: key)
            unread = []
            return
        }
        unread = (try? ledger.unreadEntities(since: mark)) ?? []
    }

    /// Called when the feed has actually been on screen.
    ///
    /// The new mark is read from the log *before* the rows are drawn, not stamped as "now" after:
    /// an event landing while the screen is open would otherwise be marked read having never been
    /// rendered. Taking the mark first means it is at worst shown again, which is the harmless
    /// direction to be wrong in.
    func markRead(upTo mark: Int64) {
        guard mark > self.mark else { return }
        defaults.set(mark, forKey: key)
        unread = []
    }

    /// The mark to pass to `markRead` once the feed has been seen.
    func pendingMark(from ledger: LedgerStore) -> Int64 {
        (try? ledger.latestReceivedAt()) ?? mark
    }

    private var mark: Int64 { Int64(defaults.integer(forKey: key)) }

    /// Absent, not zero: a device whose log is genuinely empty has a legitimate mark of 0, and
    /// treating that as "never looked" would re-run the first-run adoption on every launch until
    /// the first event arrived.
    private var hasMark: Bool { defaults.object(forKey: key) != nil }
}
