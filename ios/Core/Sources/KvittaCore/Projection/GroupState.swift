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
    /// The free-text "om gruppen" blurb, set via `GroupUpdated.description`. Nil when unset.
    public var about: String?
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

    /// Folds every non-deleted expense and every payment into a net position per member,
    /// **per currency** — each event lands in the bucket of its own currency, and buckets never
    /// mix (M7: a group holds SEK and DKK side by side; an expense is still exactly one currency).
    ///
    /// Each expense credits its payers and debits its share holders. Because the payload type
    /// guarantees those two totals are equal, every expense contributes exactly zero to its
    /// bucket's total — which is why every bucket sums to zero no matter what sequence produced
    /// it (property test P1, per bucket).
    /// `asOf` decides which *pending* payments count (aged past the auto-confirm window) —
    /// see `Payment.countsTowardBalances(asOf:)`. Defaults to today, which is what every screen
    /// wants; tests pass a fixed date so the answer never depends on when they run.
    public func balances(asOf: CalendarDate = CalendarDate(Date())) -> GroupBalances {
        var buckets: [CurrencyCode: [MemberID: Int64]] = [:]

        func bucket(_ code: CurrencyCode) -> [MemberID: Int64] {
            if let existing = buckets[code] { return existing }
            // Every member appears in every bucket at zero, so "kvitt" renders as 0 rather than
            // as absence — and the settled count over a bucket means something.
            var fresh: [MemberID: Int64] = [:]
            fresh.reserveCapacity(members.count)
            for memberId in members.keys { fresh[memberId] = 0 }
            return fresh
        }

        for expense in expenses.values where !expense.isDeleted {
            var byMember = bucket(expense.currency)
            for line in expense.payload.payers {
                byMember[line.memberId, default: 0] += line.amountMinor
            }
            for line in expense.payload.shares {
                byMember[line.memberId, default: 0] -= line.amountMinor
            }
            buckets[expense.currency] = byMember
        }

        for payment in payments.values where payment.countsTowardBalances(asOf: asOf) {
            var byMember = bucket(payment.currency)
            // Paying down a debt moves the payer toward zero from below.
            byMember[payment.fromMemberId, default: 0] += payment.amountMinor
            byMember[payment.toMemberId, default: 0] -= payment.amountMinor
            buckets[payment.currency] = byMember
        }

        // An empty group still has a ledger: its primary currency, everyone at zero.
        if buckets.isEmpty {
            buckets[currency] = bucket(currency)
        }

        return GroupBalances(byCurrency: buckets.map { Balances(currency: $0.key, byMember: $0.value) })
    }

    /// The bucket of the group's primary currency — the one `GroupCreated` fixed, the default
    /// for new expenses, and the ≈-conversion target. Always present.
    public func primaryBalances(asOf: CalendarDate = CalendarDate(Date())) -> Balances {
        balances(asOf: asOf).balances(in: currency) ?? Balances(currency: currency, byMember: [:])
    }

    /// Payments still waiting on their payee, newest first — the card that asks for a decision.
    public func paymentsAwaitingConfirmation(asOf: CalendarDate = CalendarDate(Date())) -> [Payment] {
        payments.values
            .filter { $0.awaitsConfirmation(asOf: asOf) }
            .sorted { left, right in
                left.date == right.date ? left.id < right.id : left.date > right.date
            }
    }

    /// Every line behind one member's balance **in one currency**, oldest first, with a running
    /// total that ends on exactly the number shown in the UI. Currency-scoped because a running
    /// total across SEK and DKK lines would be adding kronor to kroner — a number with no meaning.
    /// This is the Balansgranskning screen and the CSV export.
    public func breakdown(
        for memberId: MemberID,
        in entryCurrency: CurrencyCode,
        asOf: CalendarDate = CalendarDate(Date())
    ) -> [LedgerEntry] {
        struct Contribution {
            let source: LedgerEntry.Source
            let date: CalendarDate
            let title: String
            let delta: Int64
        }

        var contributions: [Contribution] = []

        for expense in expenses.values where !expense.isDeleted && expense.currency == entryCurrency {
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

        // Only payments that count: the running total must land on exactly the number the
        // balance shows, and a pending payment is not in that number yet.
        for payment in payments.values
        where payment.currency == entryCurrency && payment.countsTowardBalances(asOf: asOf) {
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
                    // The user's own note, or nothing. Deliberately not the payment method:
                    // `method` is a raw wire string ("swish", and whatever a newer client
                    // invents), so falling back to it puts an unlocalised enum value on screen.
                    // A payment with no note gets its label from the UI, via `source`.
                    title: payment.payload.note ?? "",
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

    /// Suggested settle-up transfers for this group, per currency bucket in currency order.
    /// Display only — it creates no events. Buckets never net against each other: a SEK debt is
    /// paid in SEK, full stop, because the alternative is a transfer at a rate somebody disputes.
    public func suggestedTransfers(asOf: CalendarDate = CalendarDate(Date())) -> [SuggestedTransfer] {
        balances(asOf: asOf).byCurrency.flatMap { DebtSimplifier.simplify($0) }
    }
}
