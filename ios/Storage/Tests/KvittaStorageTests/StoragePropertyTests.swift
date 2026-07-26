import Foundation
import Testing
import KvittaCore
import KvittaCoreTestSupport
@testable import KvittaStorage

/// The property that makes the storage layer trustworthy.
///
/// Everything the user sees is folded out of the log, so the only thing storage has to get right
/// is handing the log back unchanged and in the right order. This checks that end to end against
/// the same randomly generated histories `KvittaCore`'s property tests use — which is why the
/// generator was promoted to a shared library rather than copied: two definitions of "a valid
/// history" would drift, and then agreement here would prove nothing.
@Suite("Storage properties")
struct StoragePropertyTests {
    private let iterations: UInt64 = 1_000

    @Test("Writing a history and reading it back reproduces the projection exactly")
    func persistAndReloadIsIdentity() throws {
        for seed in 0..<iterations {
            let history = try EventSequenceGenerator.make(seed: seed)

            let store = try EventStore.inMemory()
            try store.append(history.events, origin: .remote)
            let loaded = try store.allEvents()

            #expect(loaded.rejected.isEmpty, "seed \(seed): \(loaded.rejected)")

            // The generator re-delivers earlier events on purpose, as an overlapping sync page
            // would; the database keeps one row each. Compare against the same de-duplicated set
            // in serverSeq order, which is the order the database hands rows back in.
            var seen = Set<EventID>()
            let expected = history.events
                .filter { seen.insert($0.eventId).inserted }
                .sorted { ($0.serverSeq ?? .max) < ($1.serverSeq ?? .max) }

            #expect(loaded.events == expected, "seed \(seed): stored events differ")
            #expect(
                Projector.replay(loaded.events) == Projector.replay(expected),
                "seed \(seed): projections differ"
            )
        }
    }

    @Test("Storing a history twice leaves the database and the projection untouched")
    func doubleWriteIsANoOp() throws {
        for seed in 0..<iterations {
            let history = try EventSequenceGenerator.make(seed: seed)
            let store = try EventStore.inMemory()

            try store.append(history.events, origin: .remote)
            let firstPass = try store.allEvents().events
            let firstCount = try store.eventCount()

            try store.append(history.events, origin: .remote)

            #expect(try store.eventCount() == firstCount, "seed \(seed)")
            #expect(try store.allEvents().events == firstPass, "seed \(seed)")
            #expect(
                Projector.replay(try store.allEvents().events) == Projector.replay(firstPass),
                "seed \(seed)"
            )
        }
    }

    @Test("Every event survives encoding to disk and back byte for byte")
    func eventsRoundTripThroughStorage() throws {
        for seed in 0..<200 {
            let history = try EventSequenceGenerator.make(seed: UInt64(seed), maxActions: 20)
            let store = try EventStore.inMemory()
            try store.append(history.events, origin: .remote)

            let loaded = try store.allEvents().events
            for event in loaded {
                let original = history.events.first { $0.eventId == event.eventId }
                #expect(event == original, "seed \(seed): event \(event.eventId) changed on disk")
            }
        }
    }
}
