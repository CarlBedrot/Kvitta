import Foundation
import Testing
import KvittaCore
@testable import Kvitta

/// A group's colour is a function of its id and nothing else: the same on every phone, the same
/// after every launch. `hashValue` would have been the obvious tool and the wrong one — Swift
/// reseeds it per process, so the palette would have been reshuffled every time the app opened.
struct GroupTintTests {

    @Test func sameIdAlwaysGetsTheSameTint() {
        let uuid = UUID(uuidString: "7D2B5C14-9E3A-4F6B-8C1D-2A3B4C5D6E7F")!
        let first = Theme.GroupTint.index(for: GroupID(rawValue: uuid))
        let again = Theme.GroupTint.index(for: GroupID(rawValue: uuid))
        #expect(first == again)
        #expect((0..<Theme.GroupTint.palette.count).contains(first))
    }

    @Test func differentIdsSpreadAcrossThePalette() {
        // Eight buckets: any two ids may collide, but sixty-four must not all land in one.
        let buckets = Set((0..<64).map { _ in Theme.GroupTint.index(for: GroupID()) })
        #expect(buckets.count > 1)
    }

    @Test func neighbouringIdsDiffer() {
        // Two ids one byte apart land in different buckets — the sum moves by exactly one.
        let a = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let b = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        #expect(Theme.GroupTint.index(for: GroupID(rawValue: a)) != Theme.GroupTint.index(for: GroupID(rawValue: b)))
    }
}
