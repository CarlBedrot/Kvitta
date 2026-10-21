import Foundation
import Testing
import KvittaCore
@testable import Kvitta

/// Archiving is device-local housekeeping (README §3.5): no event, just a set of ids that must
/// survive a relaunch and never spill across groups.
@MainActor
struct ArchivedGroupsStoreTests {

    private func freshDefaults() -> UserDefaults {
        let name = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("A group starts unarchived, archives, and restores")
    func archiveAndRestore() {
        let store = ArchivedGroupsStore(defaults: freshDefaults())
        let group = GroupID()

        #expect(!store.isArchived(group))
        store.archive(group)
        #expect(store.isArchived(group))
        store.restore(group)
        #expect(!store.isArchived(group))
    }

    @Test("Archiving is scoped to the group archived, never its neighbours")
    func archivingIsScoped() {
        let store = ArchivedGroupsStore(defaults: freshDefaults())
        let trip = GroupID(), rent = GroupID()

        store.archive(trip)
        #expect(store.isArchived(trip))
        #expect(!store.isArchived(rent))
    }

    @Test("Archived groups survive a relaunch")
    func survivesRelaunch() {
        let defaults = freshDefaults()
        let group = GroupID()
        ArchivedGroupsStore(defaults: defaults).archive(group)

        let reopened = ArchivedGroupsStore(defaults: defaults)
        #expect(reopened.isArchived(group))
    }

    @Test("Archiving twice, or restoring something never archived, is a no-op")
    func redundantCallsAreHarmless() {
        let store = ArchivedGroupsStore(defaults: freshDefaults())
        let group = GroupID()

        store.archive(group)
        store.archive(group)
        #expect(store.archived == Set([group]))

        store.restore(GroupID())
        #expect(store.archived == Set([group]))
    }
}
