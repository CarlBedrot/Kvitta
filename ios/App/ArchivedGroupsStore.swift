import Foundation
import KvittaCore

/// Groups swiped off the Grupper list (README §3.5, "VISA ARKIVERADE").
///
/// Deliberately not an event, for the same reason as `UnreadStore` and the Swish number:
/// archiving is this device's own housekeeping, not a fact about the group. It hides a group from
/// the list only — membership, balances and the ledger itself are untouched, so there is nothing
/// to write and nothing to sync. A set of ids in `UserDefaults` is the whole mechanism.
@MainActor
@Observable
final class ArchivedGroupsStore {
    private let defaults: UserDefaults
    private let key = "se.kvitta.archivedGroups"

    private(set) var archived: Set<GroupID>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.stringArray(forKey: key) ?? []
        archived = Set(saved.compactMap { GroupID(uuidString: $0) })
    }

    func isArchived(_ groupId: GroupID) -> Bool {
        archived.contains(groupId)
    }

    func archive(_ groupId: GroupID) {
        guard archived.insert(groupId).inserted else { return }
        persist()
    }

    func restore(_ groupId: GroupID) {
        guard archived.remove(groupId) != nil else { return }
        persist()
    }

    private func persist() {
        defaults.set(archived.map(\.description), forKey: key)
    }
}
