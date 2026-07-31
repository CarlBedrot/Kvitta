import Foundation
import KvittaCore

// App-side conveniences layered on top of the Core projection. These only *read* the projection
// and delegate every number to `balances()` — no money math lives here (CLAUDE.md: never sum
// balances yourself). Kept in the App target so `ios/Core` stays untouched and dependency-free.

extension GroupState {
    /// The member representing the local user in this group — the one whose account is linked to
    /// this device. `NewGroupSheet` creates it as "Du". `nil` for a group with no linked member
    /// (e.g. imported from a friend, or older seed data).
    func me(for userId: UserID) -> Member? {
        members.values.first { $0.linkedUserId == userId }
    }

    /// The local user's net position in this group, one `Money` per currency bucket, primary
    /// currency first. Zero-in-primary when there is no linked member yet.
    func nets(for userId: UserID) -> [Money] {
        guard let me = me(for: userId) else { return [.zero(currency)] }
        let all = balances().byCurrency.map { $0.money(for: me.id) }
        // Primary first, then the rest in bucket order — every screen leads with the same line.
        return all.sorted { lhs, rhs in
            if lhs.currency == currency { return true }
            if rhs.currency == currency { return false }
            return lhs.currency.code < rhs.currency.code
        }
    }

    /// The primary-currency net alone, for contexts that lead with one number.
    func net(for userId: UserID) -> Money {
        nets(for: userId).first ?? .zero(currency)
    }

    /// When the group last changed, for sorting the home list. `nil` means no expenses or
    /// payments yet — a freshly created, empty group.
    var lastActivity: Timestamp? {
        var latest: Timestamp?
        for expense in expenses.values {
            latest = maxTimestamp(latest, expense.createdAt, expense.lastModifiedAt)
        }
        for payment in payments.values {
            latest = maxTimestamp(latest, payment.recordedAt)
        }
        return latest
    }

    private func maxTimestamp(_ values: Timestamp?...) -> Timestamp? {
        values.compactMap { $0 }.max()
    }
}

// Let ids drive `.sheet(item:)` presentations (Balansgranskning, Utgiftsdetalj). App-side only;
// Core stays free of UI-serving conformances.

extension MemberID: @retroactive Identifiable {
    public var id: UUID { rawValue }
}

extension ExpenseID: @retroactive Identifiable {
    public var id: UUID { rawValue }
}

extension LedgerState {
    /// Groups newest-activity first, as the home screen shows them. Empty groups (no activity)
    /// sort last, tie-broken by name so two devices with the same log render the same order.
    var groupsByLastActivity: [GroupState] {
        groups.values.sorted { left, right in
            switch (left.lastActivity, right.lastActivity) {
            case let (l?, r?) where l != r: return l > r
            case (.some, .none): return true
            case (.none, .some): return false
            default:
                return left.name == right.name ? left.id < right.id : left.name < right.name
            }
        }
    }
}
