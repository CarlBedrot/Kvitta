import Foundation

/// A group where you owe somebody money.
public struct DebtReminder: Hashable, Sendable {
    public let groupId: GroupID
    public let groupName: String
    /// What you owe, as a positive amount.
    public let owed: Money

    public init(groupId: GroupID, groupName: String, owed: Money) {
        self.groupId = groupId
        self.groupName = groupName
        self.owed = owed
    }
}

/// Decides what is worth reminding somebody about.
///
/// Pure, and separate from the scheduling, because the interesting question is *what* to remind
/// about and that should be testable without a notification centre or a device.
public enum ReminderPlanner {

    /// The groups where this user owes money, largest debt first.
    ///
    /// Only debts you owe — never money owed *to* you. A reminder about that would be nagging
    /// someone else through your own phone, on a schedule they never agreed to, about a number
    /// they cannot see. This app is for a friend group; the product principles are explicit that
    /// it exists to stop money being awkward, not to automate the awkwardness.
    public static func outstanding(in state: LedgerState, for userId: UserID) -> [DebtReminder] {
        state.groups.values
            .flatMap { group -> [DebtReminder] in
                guard let me = group.members.values.first(where: { $0.linkedUserId == userId }),
                      me.isActive else { return [] }

                // One reminder per currency you owe in — a mixed group can have you square in
                // SEK and behind in DKK, and those are two different debts to two intents.
                // Negative is owing. Zero is settled, and settled is the state this whole app is
                // trying to reach — never remind anyone about it.
                return group.balances().byCurrency.compactMap { bucket in
                    let balance = bucket.money(for: me.id)
                    guard balance.amountMinor < 0 else { return nil }
                    return DebtReminder(
                        groupId: group.id,
                        groupName: group.name,
                        owed: Money(amountMinor: -balance.amountMinor, currency: balance.currency)
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.owed.amountMinor != rhs.owed.amountMinor {
                    return lhs.owed.amountMinor > rhs.owed.amountMinor
                }
                // Deterministic ties, so a reminder does not shuffle between launches.
                return lhs.groupId.rawValue.uuidString < rhs.groupId.rawValue.uuidString
            }
    }
}
