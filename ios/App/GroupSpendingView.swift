import SwiftUI
import KvittaCore

/// The Spending composition, scoped to this group's expenses or settled repayments.
struct GroupSpendingView: View {
    let group: GroupState
    let balances: GroupBalances
    let meId: MemberID?
    let paymentsMode: Bool
    let onAudit: () -> Void
    @State private var selectedCurrency: CurrencyCode?
    @State private var weekOffset = 0
    @State private var selectedDay: Int?

    private var currency: CurrencyCode { selectedCurrency ?? group.currency }
    private var report: ExpenseReport { ExpenseReport(groups: [group]) }
    private var days: ClosedRange<Int> { ExpenseReport.week(containing: CalendarDate(Date()), offset: weekOffset) }
    private var items: [ExpenseReport.Item] { report.filtered(currency: currency, days: days) }
    private var repayments: [Payment] { GroupPaymentReport(group: group, currency: currency, days: days).payments }
    private var net: Int64? {
        meId.map { balances.balances(in: currency)?.money(for: $0).amountMinor ?? 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(paymentsMode ? "Betalningar" : "Utgifter")
                .textCase(.uppercase).font(Editorial.heading(30)).foregroundStyle(Editorial.paper)
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { currencyMenu; periodControls }
                VStack(alignment: .leading, spacing: 8) { currencyMenu; periodControls }
            }
            EditorialPanel(fill: Editorial.coral, padding: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    if paymentsMode {
                        EditorialMetric(title: String(localized: "Avräknade återbetalningar"),
                                        value: amount(GroupPaymentReport.total(repayments)), badge: "\(repayments.count)")
                        if let net {
                            Button(action: onAudit) {
                                EditorialMetric(title: net > 0 ? String(localized: "Du ska få · nu") : net < 0 ? String(localized: "Du ska betala · nu") : String(localized: "Kvitt"),
                                                value: amount(net == Int64.min ? nil : abs(net)), badge: currency.code)
                            }.buttonStyle(.plain).accessibilityHint("Visa saldohistorik")
                        }
                    } else {
                        EditorialMetric(title: String(localized: "Gemensamma utgifter"), value: amount(ExpenseReport.total(items)), badge: "\(items.count)")
                        EditorialMetric(title: String(localized: "Största utgiften"), value: items.map(\.amountMinor).max().map { amount($0) } ?? "—", badge: currency.code)
                    }
                    EditorialWeekChart(items: items, days: days, currency: currency,
                                       payments: paymentsMode ? repayments : nil, selectedDay: $selectedDay)
                }
            }
        }
        .onChange(of: selectedCurrency) { _, _ in selectedDay = nil }
        .onChange(of: weekOffset) { _, _ in selectedDay = nil }
        .onChange(of: paymentsMode) { _, _ in selectedDay = nil }
    }

    private var currencyMenu: some View {
        Menu {
            ForEach(report.currencies, id: \.self) { code in
                Button(code.code) { selectedCurrency = code }
            }
        } label: {
            Label(currency.code, systemImage: "chevron.down")
                .font(.caption.weight(.semibold)).foregroundStyle(Editorial.coal)
                .padding(.horizontal, 16).frame(minHeight: 44).background(Editorial.paper, in: .capsule)
        }.accessibilityLabel("Valuta")
    }

    private var periodControls: some View {
        HStack(spacing: 4) {
            Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("Föregående vecka")
            Text(weekOffset == 0 ? String(localized: "Den här veckan") : ExpenseReport.label(for: days.lowerBound))
                .font(.caption.weight(.medium)).lineLimit(2)
            Button { weekOffset += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(weekOffset >= 0).accessibilityLabel("Nästa vecka")
        }.foregroundStyle(Editorial.coal).background(Editorial.paper, in: .capsule)
    }

    private func amount(_ minor: Int64?) -> String {
        minor.map { MoneyFormat.string($0, currency, explicit: true) } ?? "—"
    }
}

struct GroupRepaymentHistory: View {
    let group: GroupState

    var body: some View {
        if !group.payments.isEmpty {
            Text("Alla återbetalningar").font(Editorial.heading(24)).foregroundStyle(Editorial.paper)
            ForEach(group.paymentsByDate) { payment in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 18))
                        .frame(width: 40, height: 40).foregroundStyle(Editorial.coal)
                        .background(Editorial.mint, in: .circle).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(name(payment.fromMemberId)) → \(name(payment.toMemberId))").font(.subheadline.weight(.semibold))
                        Text(MoneyFormat.string(payment.amountMinor, payment.currency, explicit: true)).font(.subheadline).monospacedDigit()
                        Text(ExpenseReport.label(for: payment.date.dayNumber)).font(.caption).foregroundStyle(Editorial.muted)
                        Text(status(payment)).font(.caption).foregroundStyle(Editorial.muted)
                    }
                    Spacer(minLength: 0)
                }.foregroundStyle(Editorial.paper).padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private func name(_ id: MemberID) -> String { group.members[id]?.displayName ?? "?" }
    private func status(_ payment: Payment) -> String {
        if payment.countsTowardBalances(asOf: CalendarDate(Date())) { return String(localized: "Avräknad") }
        return payment.status == .disputed ? String(localized: "Bestriden") : String(localized: "Väntar på bekräftelse")
    }
}
