import Foundation
import KvittaCore

/// A photo for each group, on this device only — the mockup's group thumbnails.
///
/// Deliberately not an event, for the same reason a Swish number is not one: events are immutable,
/// so a photo written into the log would land on every member's device forever with no way to take
/// it back — and at JPEG sizes it would also bloat a log that replays on every launch. Each person
/// picks their own picture for a group, the way each person names their own contacts.
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

    /// Stores a downscaled square, or clears the photo when `nil`. Full camera images are several
    /// megabytes; a 256-point square is what a 48-point circle actually needs.
    func set(_ data: Data?, for groupId: GroupID) {
        if let data {
            defaults.set(data, forKey: key(groupId))
        } else {
            defaults.removeObject(forKey: key(groupId))
        }
        generation += 1
    }

    private func key(_ groupId: GroupID) -> String {
        "se.kvitta.groupImage.\(groupId.rawValue.uuidString)"
    }
}
