import Foundation
import Testing
import KvittaCore
@testable import Kvitta

/// The device-local stores — small, but they hold phone numbers and display choices, and a
/// silent bug here surfaces as "the app forgot my setting", which reads as data loss.
@MainActor
struct StoreTests {

    /// A throwaway suite per test, so tests never see each other's writes or the real app's.
    private func freshDefaults() -> UserDefaults {
        let name = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - PayeeDirectory

    @Test("Remember normalises nothing but refuses what Swish would refuse")
    func rememberValidates() {
        let payees = PayeeDirectory(defaults: freshDefaults())
        let member = MemberID()

        // Stored as typed — the display keeps the human shape.
        payees.remember("070-123 45 67", for: member)
        #expect(payees.number(for: member) == "070-123 45 67")

        // Garbage is refused outright rather than remembered-and-broken.
        payees.remember("12", for: member)
        #expect(payees.number(for: member) == "070-123 45 67")
    }

    @Test("Absorb overwrites: the owner's own number beats someone else's memory of it")
    func absorbWins() {
        let payees = PayeeDirectory(defaults: freshDefaults())
        let member = MemberID()
        payees.remember("0701111111", for: member)

        payees.absorb([member: "46702222222"])
        #expect(payees.number(for: member) == "46702222222")
    }

    @Test("Forget removes exactly one member's number")
    func forgetIsScoped() {
        let payees = PayeeDirectory(defaults: freshDefaults())
        let anna = MemberID(), bertil = MemberID()
        payees.absorb([anna: "46701111111", bertil: "46702222222"])

        payees.forget(anna)
        #expect(payees.number(for: anna) == nil)
        #expect(payees.number(for: bertil) == "46702222222")
    }

    // MARK: - CurrencyDisplayStore

    @Test("Every display mode round-trips through storage")
    func displayModeRoundTrip() {
        let store = CurrencyDisplayStore(defaults: freshDefaults())
        let group = GroupID()

        #expect(store.mode(for: group) == .native)

        for mode: CurrencyDisplay in [.converted, .only(.dkk), .only(.sek), .native] {
            store.set(mode, for: group)
            #expect(store.mode(for: group) == mode)
        }
    }

    @Test("Modes are per group")
    func modesArePerGroup() {
        let store = CurrencyDisplayStore(defaults: freshDefaults())
        let mixed = GroupID(), plain = GroupID()

        store.set(.converted, for: mixed)
        #expect(store.mode(for: mixed) == .converted)
        #expect(store.mode(for: plain) == .native)
    }

    @Test("A storage value from a future build falls back to native, never crashes")
    func unknownStorageValueFallsBack() {
        let defaults = freshDefaults()
        let store = CurrencyDisplayStore(defaults: defaults)
        let group = GroupID()
        defaults.set("hologram:XRP", forKey: "se.kvitta.currencyDisplay.\(group.rawValue.uuidString)")

        #expect(store.mode(for: group) == .native)
    }
}
