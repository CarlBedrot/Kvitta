import Foundation
import KvittaCore
import UIKit

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

    /// Decoded and decompressed once, drawn many times. `UIImage(data:)` inside a view body
    /// re-decodes a ~200 kB JPEG on every render — during a scroll that is jank you can feel,
    /// which is exactly the "smooth and fast" promise this app is built on.
    @ObservationIgnored
    private var decoded: [GroupID: UIImage] = [:]

    func image(for groupId: GroupID) -> Data? {
        _ = generation
        return defaults.data(forKey: key(groupId))
    }

    /// The photo ready to draw: decoded, decompressed off the JPEG, and cached until `set`.
    func uiImage(for groupId: GroupID) -> UIImage? {
        _ = generation
        if let cached = decoded[groupId] { return cached }
        guard let data = image(for: groupId), let raw = UIImage(data: data) else { return nil }
        // preparingForDisplay does the JPEG decompression now instead of at first draw.
        let ready = raw.preparingForDisplay() ?? raw
        decoded[groupId] = ready
        return ready
    }

    /// Stores a downscaled photo, or clears it when `nil`. Full camera images are several
    /// megabytes; 1200 points on the long side covers the card banner and the full-image viewer.
    func set(_ data: Data?, for groupId: GroupID) {
        if let data {
            defaults.set(data, forKey: key(groupId))
        } else {
            defaults.removeObject(forKey: key(groupId))
        }
        decoded[groupId] = nil
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
