import Foundation

/// One group, projected from its event log.
///
/// Balances are computed on demand rather than cached. At this data size the fold is measured in
/// microseconds, and a derived value that cannot go stale is worth more than one that is fast.
public struct GroupState: Hashable, Sendable, Identifiable {
    public let id: GroupID
    public var name: String
    public var currency: CurrencyCode
    public var coverPhotoRef: String?
    public var members: [MemberID: Member]
    public var expenses: [ExpenseID: Expense]
    public var payments: [PaymentID: Payment]
    /// Highest `serverSeq` folded into this state. `nil` means nothing acknowledged yet.
    public var lastAppliedSeq: Int64?

    public init(
        id: GroupID,
        name: String,
        currency: CurrencyCode,
        coverPhotoRef: String? = nil,
        members: [MemberID: Member] = [:],
        expenses: [ExpenseID: Expense] = [:],
        payments: [PaymentID: Payment] = [:],
        lastAppliedSeq: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.currency = currency
        self.coverPhotoRef = coverPhotoRef
        self.members = members
        self.expenses = expenses
        self.payments = payments
        self.lastAppliedSeq = lastAppliedSeq
    }

    // MARK: - Ordered views
    //
    // Dictionaries have no order, so every list the UI might show is sorted explicitly here.
    // Two devices with the same log must render the same list.

    public var membersByName: [Member] {
        members.values.sorted {
            $0.displayName == $1.displayName ? $0.id < $1.id : $0.displayName < $1.displayName
        }
    }

    public var activeMembers: [Member] {
        membersByName.filter(\.isActive)
    }

    /// Newest first, as the group screen shows them.
    public var visibleExpenses: [Expense] {
        expenses.values
            .filter { !$0.isDeleted }
            .sorted { left, right in
                left.date == right.date ? left.id < right.id : left.date > right.date
            }
    }

    public var deletedExpenses: [Expense] {
        expenses.values
            .filter(\.isDeleted)
            .sorted { left, right in
                left.date == right.date ? left.id < right.id : left.date > right.date
            }
    }

    public var paymentsByDate: [Payment] {
        payments.values.sorted { left, right in
            left.date == right.date ? left.id < right.id : left.date > right.date
        }
    }

    // MARK: - Derived money

    /// Folds every non-deleted expense and every payment into a net position per member.
    ///
    /// Each expense credits its payers and debits its share holders. Because the payload type
    /// guarantees those two totals are equal, every expense contributes exactly zero to the group
    /// total — which is why the whole thing sums to zero no matter what sequence produced it.
    public func balances() -> Balances {
        var byMember: [MemberID: Int64] = [:]
        byMember.reserveCapacity(members.count)
        for memberId in members.keys {
            byMember[memberId] = 0
        }

        for expense in expenses.values where !expense.isDeleted {
            for line in expense.payload.payers {
                byMember[line.memberId, default: 0] += line.amountMinor
            }
            for line in expense.payload.shares {
                byMember[line.memberId, default: 0] -= line.amountMinor
            }
        }

        for payment in payments.values {
            // Paying down a debt moves the payer toward zero from below.
            byMember[payment.fromMemberId, default: 0] += payment.amountMinor
            byMember[payment.toMemberId, default: 0] -= payment.amountMinor
        }

        return Balances(currency: currency, byMember: byMember)
    }

    /// Every line behind one member's balance, oldest first, with a running total that ends on
    /// exactly the number shown in the UI. This is the Balansgranskning screen and the CSV export.
    public func breakdown(for memberId: MemberID) -> [LedgerEntry] {
        struct Contribution {
            let source: LedgerEntry.Source
            let date: CalendarDate
            let title: String
            let delta: Int64
        }

        var contributions: [Contribution] = []

        for expense in expenses.values where !expense.isDeleted {
            let delta = expense.payload.paid(by: memberId) - expense.payload.share(of: memberId)
            guard delta != 0 || expense.payload.involvedMembers.contains(memberId) else { continue }
            contributions.append(
                Contribution(
                    source: .expense(expense.id),
                    date: expense.date,
                    title: expense.title,
                    delta: delta
                )
            )
        }

        for payment in payments.values {
            let delta: Int64
            switch memberId {
            case payment.fromMemberId: delta = payment.amountMinor
            case payment.toMemberId: delta = -payment.amountMinor
            default: continue
            }
            contributions.append(
                Contribution(
                    source: .payment(payment.id),
                    date: payment.date,
                    title: payment.payload.note ?? payment.method.rawValue,
                    delta: delta
                )
            )
        }

        let ordered = contributions.sorted { left, right in
            if left.date != right.date { return left.date < right.date }
            return GroupState.sourceOrder(left.source, right.source)
        }

        var running: Int64 = 0
        return ordered.map { contribution in
            running += contribution.delta
            return LedgerEntry(
                source: contribution.source,
                date: contribution.date,
                title: contribution.title,
                memberId: memberId,
                deltaMinor: contribution.delta,
                runningTotalMinor: running
            )
        }
    }

    /// Tie-break for two contributions on the same day: expenses before payments, then by id.
    private static func sourceOrder(_ left: LedgerEntry.Source, _ right: LedgerEntry.Source) -> Bool {
        switch (left, right) {
        case (.expense(let l), .expense(let r)): return l < r
        case (.payment(let l), .payment(let r)): return l < r
        case (.expense, .payment): return true
        case (.payment, .expense): return false
        }
    }

    /// Suggested settle-up transfers for this group. Display only — it creates no events.
    public func suggestedTransfers() -> [SuggestedTransfer] {
        DebtSimplifier.simplify(balances())
    }
}
