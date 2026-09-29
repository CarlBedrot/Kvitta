import Foundation
import KvittaCore

/// Payment numbers from mutable server profiles, plus a device-local fallback for manual members.
/// Phone numbers never enter the immutable group log.
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

    /// Keep legacy display formatting, but only store a plausible Swedish or Danish number.
    func remember(_ number: String, for memberId: MemberID) {
        guard PaymentPhoneNumber(number) != nil else { return }
        defaults.set(number, forKey: key(memberId))
        generation += 1
    }

    func forget(_ memberId: MemberID) {
        defaults.removeObject(forKey: key(memberId))
        generation += 1
    }

    private func key(_ memberId: MemberID) -> String {
        "se.kvitta.payee.\(memberId.rawValue.uuidString)"
    }
}
