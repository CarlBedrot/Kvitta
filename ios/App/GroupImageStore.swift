import Foundation
import KvittaCore

/// The group's photo as this device knows it — the local half of the *shared* group picture.
///
/// Deliberately not an event, for the same reason a Swish number is not one: events are immutable,
/// so a photo written into the log would land on every member's device forever with no way to take
/// it back — and at JPEG sizes it would also bloat a log that replays on every launch. It syncs as
/// a mutable server field instead (`GroupPhotoSyncer`), so co-members see it and anyone can
/// replace or remove it. This store is what every screen reads, which is exactly what makes the
/// photo work offline: the last known picture is simply what is remembered.
@MainActor
@Observable
final class GroupImageStore {
    private let defaults: UserDefaults

    /// Bumped on every write so views re-read. `UserDefaults` itself is not observable.
    private var generation = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func image(for groupId: GroupID) -> Data? {
        _ = generation
        return defaults.data(forKey: key(groupId))
    }

    /// Stores a downscaled photo, or clears it when `nil`. Full camera images are several
    /// megabytes; 1200 points on the long side covers the card banner and the full-image viewer.
    func set(_ data: Data?, for groupId: GroupID) {
        if let data {
            defaults.set(data, forKey: key(groupId))
        } else {
            defaults.removeObject(forKey: key(groupId))
        }
        generation += 1
    }

    // MARK: - Sync bookkeeping (written by GroupPhotoSyncer only)

    /// The server's content tag for the photo we hold, or `nil` if it never came from the server.
    func etag(for groupId: GroupID) -> String? {
        defaults.string(forKey: key(groupId) + ".etag")
    }

    func setEtag(_ etag: String?, for groupId: GroupID) {
        if let etag {
            defaults.set(etag, forKey: key(groupId) + ".etag")
        } else {
            defaults.removeObject(forKey: key(groupId) + ".etag")
        }
    }

    /// True while a local pick (or removal) has not reached the server — offline is the normal
    /// state, so intent has to survive a restart.
    func isDirty(_ groupId: GroupID) -> Bool {
        defaults.bool(forKey: key(groupId) + ".dirty")
    }

    func setDirty(_ dirty: Bool, for groupId: GroupID) {
        if dirty {
            defaults.set(true, forKey: key(groupId) + ".dirty")
        } else {
            defaults.removeObject(forKey: key(groupId) + ".dirty")
        }
    }

    private func key(_ groupId: GroupID) -> String {
        "se.kvitta.groupImage.\(groupId.rawValue.uuidString)"
    }
}
