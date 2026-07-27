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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func number(for memberId: MemberID) -> String? {
        defaults.string(forKey: key(memberId))
    }

    func remember(_ number: String, for memberId: MemberID) {
        let digits = number.filter(\.isNumber)
        guard !digits.isEmpty else { return }
        defaults.set(number, forKey: key(memberId))
    }

    func forget(_ memberId: MemberID) {
        defaults.removeObject(forKey: key(memberId))
    }

    private func key(_ memberId: MemberID) -> String {
        "se.kvitta.payee.\(memberId.rawValue.uuidString)"
    }
}
