import Foundation
import Testing
import KvittaCoreTestSupport
@testable import KvittaCore

/// The CSV export — the audit trail that leaves the app. What matters: it reconciles to the
/// öre with the balances screen, and it survives a spreadsheet.
@Suite("Group CSV export")
struct GroupCSVTests {

    private func makeGroup() throws -> GroupState {
        var factory = EventFactory()
        var events: [EventEnvelope] = [
            factory.groupCreated(),
            factory.memberAdded(Fixtures.member(1), name: "Du", linkedUserId: Fixtures.authorId),
            factory.memberAdded(Fixtures.member(2), name: "Jonas; \"testaren\""),
            factory.memberAdded(Fixtures.member(3), name: "Sara")
        ]
        events.append(factory.expenseCreated(Fixtures.expense(1), try ExpensePayload.make(
            description: "Systembolaget",
            categoryId: "alkohol",
            date: CalendarDate(year: 2026, month: 7, day: 20)!,
            total: Money(amountMinor: 43_700, currency: .sek),
            paidBy: Fixtures.member(1),
            splitEquallyAmong: [Fixtures.member(1), Fixtures.member(2), Fixtures.member(3)]
        )))
        events.append(factory.paymentRecorded(Fixtures.payment(1), try PaymentRecordedPayload(
            fromMemberId: Fixtures.member(2),
            toMemberId: Fixtures.member(1),
            currency: .sek,
            amountMinor: 10_000,
            date: CalendarDate(year: 2026, month: 7, day: 21)!,
            method: .swish
        )))
        return try #require(Projector.replay(events).groups[Fixtures.groupId])
    }

    @Test("Rows reconcile: the Saldo line is exactly the balances screen")
    func saldoMatchesBalances() throws {
        let group = try makeGroup()
        let asOf = CalendarDate(year: 2026, month: 7, day: 21)!
        let csv = GroupCSV.file(for: group, in: .sek, asOf: asOf)
        let lines = csv.split(separator: "\n")

        // Header + expense + payment + saldo. The payment was recorded by the payer at a
        // placeholder-free payee... member(1) is linked to the author, so payer-recorded to
        // the author's own member is payee-recorded → confirmed → counts.
        #expect(lines.count == 4)

        let saldo = lines.last!.split(separator: ";", omittingEmptySubsequences: false)
        // Du: paid 437,00, share 145,67, received 100,00 → +191,33... minus: received means
        // balance goes down: 437,00 − 145,67 − 100,00 = 191,33.
        #expect(saldo[6] == "191,33")
        let balances = try #require(group.balances(asOf: asOf).balances(in: .sek))
        #expect(GroupCSV.decimal(balances.amountMinor(for: Fixtures.member(1))) == "191,33")
    }

    @Test("Member deltas on an expense row sum to zero")
    func expenseRowSumsToZero() throws {
        let group = try makeGroup()
        let csv = GroupCSV.file(for: group, in: .sek, asOf: CalendarDate(year: 2026, month: 7, day: 21)!)
        let expenseRow = csv.split(separator: "\n")[1]
            .split(separator: ";", omittingEmptySubsequences: false)

        let deltas = expenseRow[6...].map { field -> Int64 in
            let cleaned = field.replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: ",", with: "")
            return Int64(cleaned) ?? 0
        }
        #expect(deltas.reduce(0, +) == 0)
    }

    @Test("A name containing the separator and quotes survives quoting")
    func escaping() throws {
        let group = try makeGroup()
        let csv = GroupCSV.file(for: group, in: .sek, asOf: Fixtures.date)
        #expect(csv.contains("\"Jonas; \"\"testaren\"\"\""))
    }

    @Test("A pending payment appears as väntar with empty money columns")
    func pendingPaymentIsVisibleButUncounted() throws {
        var factory = EventFactory()
        let payee = UserID(uuidString: "00000000-0000-0000-000b-000000000009")!
        var events: [EventEnvelope] = [
            factory.groupCreated(),
            factory.memberAdded(Fixtures.member(1), name: "Du", linkedUserId: Fixtures.authorId),
            factory.memberAdded(Fixtures.member(2), name: "Sara", linkedUserId: payee)
        ]
        events.append(factory.paymentRecorded(Fixtures.payment(1), try PaymentRecordedPayload(
            fromMemberId: Fixtures.member(1),
            toMemberId: Fixtures.member(2),
            currency: .sek,
            amountMinor: 5_000,
            date: Fixtures.date,
            method: .swish
        )))
        let group = try #require(Projector.replay(events).groups[Fixtures.groupId])

        let csv = GroupCSV.file(for: group, in: .sek, asOf: Fixtures.date)
        let paymentRow = csv.split(separator: "\n")[1]
            .split(separator: ";", omittingEmptySubsequences: false)
        #expect(paymentRow[5] == "väntar")
        #expect(paymentRow[6] == "" && paymentRow[7] == "")
    }

    @Test("Integer-to-decimal rendering", arguments: [
        (14_567 as Int64, "145,67"),
        (-5, "-0,05"),
        (0, "0,00"),
        (100, "1,00"),
        (-1_000_000, "-10000,00")
    ])
    func decimals(minor: Int64, expected: String) {
        #expect(GroupCSV.decimal(minor) == expected)
    }
}
