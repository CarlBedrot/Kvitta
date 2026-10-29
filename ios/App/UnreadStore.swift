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
/// Two layers, both local-only:
/// - a watermark (the `receivedAt` of the newest event this device had heard about the last time
///   everything was caught up) — advanced only by "Läs alla", never by merely opening the tab.
/// - a set of entity ids read individually since that watermark, because Steven's cards (04) stay
///   pink until *that* notification is opened, not until the whole feed has been glanced at.
///
/// Both need no network and no account — the app without an account is the offline app and must
/// stay fully functional.
@MainActor
@Observable
final class UnreadStore {
    private let defaults: UserDefaults
    private let markKey = "se.kvitta.activity.lastSeenReceivedAt"
    private let readOverridesKey = "se.kvitta.activity.readEntityIds"

    /// The unread entity ids, recomputed rather than stored wholesale. A cached count would be a
    /// second copy of a truth the log already holds, free to drift from it — the same argument
    /// that keeps projections out of the database.
    private(set) var unread: Set<UUID> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var count: Int { unread.count }

    /// The unread entries that the feed will actually list.
    func count(within entries: [FeedEntry]) -> Int {
        entries.reduce(0) { $0 + (unread.contains($1.id) ? 1 : 0) }
    }

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
            defaults.set(pendingMark(from: ledger), forKey: markKey)
            defaults.removeObject(forKey: readOverridesKey)
            unread = []
            return
        }
        let sinceMark = (try? ledger.unreadEntities(since: mark)) ?? []
        unread = sinceMark.subtracting(readOverrides)
    }

    /// A single card opened. It stays read even though older, still-unopened cards above or
    /// below it stay pink — the watermark alone cannot say that, so the id is kept on the side
    /// until "Läs alla" folds it back in.
    func markRead(_ entityId: UUID) {
        guard unread.contains(entityId) else { return }
        var overrides = readOverrides
        overrides.insert(entityId)
        defaults.set(overrides.map(\.uuidString), forKey: readOverridesKey)
        unread.remove(entityId)
    }

    /// "Läs alla": catches the watermark up to now. The per-card overrides it was tracking become
    /// moot the moment the watermark passes them, so they are dropped rather than left to grow.
    func markAllRead(from ledger: LedgerStore) {
        defaults.set(pendingMark(from: ledger), forKey: markKey)
        defaults.removeObject(forKey: readOverridesKey)
        unread = []
    }

    private var mark: Int64 { Int64(defaults.integer(forKey: markKey)) }

    /// Absent, not zero: a device whose log is genuinely empty has a legitimate mark of 0, and
    /// treating that as "never looked" would re-run the first-run adoption on every launch until
    /// the first event arrived.
    private var hasMark: Bool { defaults.object(forKey: markKey) != nil }

    private func pendingMark(from ledger: LedgerStore) -> Int64 {
        (try? ledger.latestReceivedAt()) ?? mark
    }

    private var readOverrides: Set<UUID> {
        Set((defaults.stringArray(forKey: readOverridesKey) ?? []).compactMap(UUID.init))
    }
}
