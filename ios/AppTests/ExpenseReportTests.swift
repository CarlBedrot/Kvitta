import Foundation
import Testing
import KvittaCore
import KvittaStorage
@testable import Kvitta

struct ExpenseReportTests {
    private func item(_ amount: Int64, currency: CurrencyCode = .sek,
                      date: String = "2026-09-29", category: String = "restaurang",
                      title: String = "Dinner", group: String = "Home") -> ExpenseReport.Item {
        .init(id: ExpenseID(), groupId: GroupID(), groupName: group, title: title,
              categoryId: category, date: CalendarDate(iso8601: date)!, amountMinor: amount,
              currency: currency, author: "Carl")
    }

    @Test func currencySearchAndCategoryScopesDoNotLeak() {
        let report = ExpenseReport(items: [item(1999), item(99999, currency: .dkk),
                                           item(250, category: "fika", title: "Coffee")])
        #expect(ExpenseReport.total(report.filtered(currency: .sek)) == 2249)
        #expect(ExpenseReport.total(report.filtered(currency: .dkk)) == 99999)
        #expect(report.filtered(currency: .sek, category: "fika", search: " coffee ").count == 1)
        #expect(report.filtered(currency: .sek, category: "fika", search: "Dinner").isEmpty)
        #expect(report.filtered(currency: .sek, search: "HOME").count == 2)
    }

    @Test func weeksCrossYearAndLeapDayWithoutTimeZoneArithmetic() {
        let date = CalendarDate(iso8601: "2026-01-01")!
        let week = ExpenseReport.week(containing: date)
        #expect(week.lowerBound == CalendarDate(iso8601: "2025-12-29")!.dayNumber)
        #expect(week.upperBound == CalendarDate(iso8601: "2026-01-04")!.dayNumber)
        #expect(ExpenseReport.week(containing: date, offset: -1).upperBound == week.lowerBound - 1)
        let leap = ExpenseReport.week(containing: CalendarDate(iso8601: "2024-02-29")!)
        #expect(leap.contains(CalendarDate(iso8601: "2024-03-03")!.dayNumber))
        #expect(!leap.contains(CalendarDate(iso8601: "2024-03-04")!.dayNumber))
    }

    @Test func exactDailyTotalsConserveEveryMinorUnit() {
        let entries = (1...28).map { item(Int64($0 * 137), date: String(format: "2026-09-%02d", $0), category: $0 % 2 == 0 ? "fika" : "restaurang") }
        let report = ExpenseReport(items: entries)
        for anchor in ["2026-09-01", "2026-09-14", "2026-09-28"] {
            let week = ExpenseReport.week(containing: CalendarDate(iso8601: anchor)!)
            let whole = report.filtered(currency: .sek, days: week)
            let daily = week.map { ExpenseReport.total(report.filtered(currency: .sek, days: $0...$0))! }.reduce(0, +)
            #expect(daily == ExpenseReport.total(whole))
            let categories = ["fika", "restaurang"].map { ExpenseReport.total(report.filtered(currency: .sek, days: week, category: $0))! }.reduce(0, +)
            #expect(categories == daily)
        }
    }

    @Test func emptyGroupKeepsItsPrimaryCurrencyAvailable() {
        let group = GroupState(id: GroupID(), name: "Copenhagen", currency: .dkk)
        #expect(ExpenseReport(groups: [group]).currencies == [.dkk])
    }

    @Test func overflowIsExplicitInsteadOfTrappingOrRounding() {
        #expect(ExpenseReport.total([item(Int64.max), item(1)]) == nil)
        #expect(ExpenseReport.total([item(9_007_199_254_740_993)]) == 9_007_199_254_740_993)
        #expect(ExpenseReport.total([]) == 0)
    }

    @Test @MainActor func ownExpensesAppearAndDeletionRemovesThem() throws {
        let me = UserID(), group = GroupID(), member = MemberID(), expense = ExpenseID()
        let ledger = LedgerStore(store: try EventStore.inMemory(), authorId: me)
        try ledger.record(.groupCreated(GroupCreatedPayload(name: "Home", currency: .sek)), entityId: group.rawValue, in: group)
        try ledger.record(.memberAdded(MemberAddedPayload(displayName: "Carl", linkedUserId: me)), entityId: member.rawValue, in: group)
        let payload = try ExpensePayload.make(description: "Dinner", categoryId: "restaurang",
                                             date: CalendarDate(iso8601: "2026-09-29")!,
                                             total: Money(amountMinor: 12345, currency: .sek),
                                             paidBy: member, splitEquallyAmong: [member])
        try ledger.record(.expenseCreated(payload), entityId: expense.rawValue, in: group)
        let report = ExpenseReport(groups: ledger.state.groupsByLastActivity)
        #expect(report.items.count == 1)
        #expect(report.items.first?.author == "Carl")
        #expect(report.items.first?.id == expense)
        try ledger.record(.expenseDeleted(EmptyPayload()), entityId: expense.rawValue, in: group)
        #expect(ExpenseReport(groups: ledger.state.groupsByLastActivity).items.isEmpty)
    }
}

struct GroupPaymentReportTests {
    private let today = CalendarDate(iso8601: "2026-09-30")!

    private func payment(_ amount: Int64, currency: CurrencyCode = .sek,
                         date: String = "2026-09-29", status: PaymentStatus = .confirmed) throws -> Payment {
        Payment(id: PaymentID(), payload: try PaymentRecordedPayload(
            fromMemberId: MemberID(), toMemberId: MemberID(), currency: currency,
            amountMinor: amount, date: CalendarDate(iso8601: date)!, method: .cash),
                recordedBy: UserID(), recordedAt: Timestamp(epochMilliseconds: 0), status: status)
    }

    @Test func periodCurrencyAndStatusMatchTheBalancePolicy() throws {
        let confirmed = try payment(100), pending = try payment(200, status: .pending)
        let disputed = try payment(300, status: .disputed), foreign = try payment(400, currency: .dkk)
        let aged = try payment(500, date: "2026-09-20", status: .pending)
        let records = [confirmed, pending, disputed, foreign, aged]
        let group = GroupState(id: GroupID(), name: "Home", currency: .sek,
                               payments: Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) }))
        let week = ExpenseReport.week(containing: today)
        let current = GroupPaymentReport(group: group, currency: .sek, days: week, asOf: today)
        #expect(current.payments.map(\.id) == [confirmed.id])
        #expect(GroupPaymentReport.total(current.payments) == 100)
        #expect(GroupPaymentReport.total(GroupPaymentReport(group: group, currency: .dkk, days: week, asOf: today).payments) == 400)
        let oldWeek = ExpenseReport.week(containing: aged.date)
        #expect(GroupPaymentReport(group: group, currency: .sek, days: oldWeek, asOf: today).payments.map(\.id) == [aged.id])
        #expect(GroupPaymentReport(group: group, currency: .sek, days: oldWeek, asOf: aged.date).payments.isEmpty)
        let other = GroupState(id: GroupID(), name: "Other", currency: .sek)
        #expect(GroupPaymentReport(group: other, currency: .sek, days: week, asOf: today).payments.isEmpty)
    }

    @Test func dailyRepaymentTotalsConserveMinorUnits() throws {
        let entries = try (1...7).map { try payment(Int64($0 * 137), date: String(format: "2026-09-%02d", 20 + $0)) }
        let daily = Set(entries.map(\.date)).map { day in GroupPaymentReport.total(entries.filter { $0.date == day })! }.reduce(0, +)
        #expect(daily == GroupPaymentReport.total(entries))
    }

    @Test func repaymentTotalsStayExactAndOverflowIsExplicit() throws {
        #expect(GroupPaymentReport.total([]) == 0)
        #expect(GroupPaymentReport.total([try payment(9_007_199_254_740_993)]) == 9_007_199_254_740_993)
        #expect(GroupPaymentReport.total([try payment(Int64.max), try payment(1)]) == nil)
    }
}
