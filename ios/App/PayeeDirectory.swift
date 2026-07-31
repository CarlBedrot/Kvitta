import Foundation
import KvittaCore

/// Swish numbers for the people you settle up with, on this device only.
///
/// Deliberately not an event. A phone number in the group log would be copied to every member's
/// device forever and could never be taken back — events are immutable — which is a lot of
/// permanence for a detail one person needs in order to press one button. It is also not the
/// group's business who has whose number.
///
/// So it lives here: remembered after the first time you type it, per member, on this phone.
@MainActor
@Observable
final class PayeeDirectory {
    private let defaults: UserDefaults

    /// Bumped when the server fetch lands, so a view already on screen re-reads. UserDefaults is
    /// not observable by itself — same pattern as `GroupImageStore`.
    private var generation = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func number(for memberId: MemberID) -> String? {
        _ = generation
        return defaults.string(forKey: key(memberId))
    }

    /// Numbers fetched from members' own profiles. They win over anything typed here: the owner
    /// of a number is a better source for it than someone else's memory of it.
    func absorb(_ numbers: [MemberID: String]) {
        for (memberId, number) in numbers {
            remember(number, for: memberId)
        }
        generation += 1
    }

    /// Stored as typed, so it still reads like a phone number later — but only once Swish would
    /// accept it. Remembering "12" would leave the button quietly missing with nothing to explain
    /// why.
    func remember(_ number: String, for memberId: MemberID) {
        guard SwishNumber.normalised(number) != nil else { return }
        defaults.set(number, forKey: key(memberId))
    }

    func forget(_ memberId: MemberID) {
        defaults.removeObject(forKey: key(memberId))
    }

    private func key(_ memberId: MemberID) -> String {
        "se.kvitta.payee.\(memberId.rawValue.uuidString)"
    }
}
