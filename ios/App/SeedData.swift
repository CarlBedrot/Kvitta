import Foundation
import KvittaCore
import KvittaStorage

/// Writes the design doc's worked example through the real write path.
///
/// 437.00 kr at Systembolaget, paid by one of three people, split equally — which the doc says
/// must come out as 145.67 / 145.67 / 145.66. Seeing those three numbers on screen is the proof
/// that the whole stack agrees: allocator, event log, SQLite, projection, and the view.
enum SeedData {
    @MainActor
    static func insert(into ledger: LedgerStore) throws {
        let groupId = GroupID()
        let members = (0..<3).map { _ in MemberID() }
        let names = ["Carl", "Jonas", "Sara"]

        try ledger.record(
            .groupCreated(GroupCreatedPayload(name: "Fjällresan", currency: .sek)),
            entityId: groupId.rawValue,
            in: groupId
        )

        for (memberId, name) in zip(members, names) {
            try ledger.record(
                .memberAdded(MemberAddedPayload(displayName: name)),
                entityId: memberId.rawValue,
                in: groupId
            )
        }

        let today = CalendarDate(Date())
        try ledger.record(
            .expenseCreated(
                try ExpensePayload.make(
                    description: "Systembolaget",
                    categoryId: "alkohol",
                    date: today,
                    total: Money(amountMinor: 43_700, currency: .sek),
                    paidBy: members[0],
                    splitEquallyAmong: members
                )
            ),
            entityId: ExpenseID().rawValue,
            in: groupId
        )

        // A settle-up, so the payment path gets exercised too.
        try ledger.record(
            .paymentRecorded(
                try PaymentRecordedPayload(
                    fromMemberId: members[1],
                    toMemberId: members[0],
                    currency: .sek,
                    amountMinor: 10_000,
                    date: today,
                    method: .swish
                )
            ),
            entityId: PaymentID().rawValue,
            in: groupId
        )
    }
}
