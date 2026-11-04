import SwiftUI
import Charts
import KvittaCore
import KvittaStorage

/// STATISTIK (Steven 15/16, README §5.2, image 11): scoped to one group, `Steven.NavTitleBar` +
/// `Steven.UnderlineTabs` (Utgifter · Kategorier · Veckorytm · Betalningar), charts in accent/coral
/// on white `Steven.Card`s. Reached from Gruppinställningar → Statistik (#151) — that screen
/// already pushes this exact initializer, so the parameter list below must keep its shape.
struct ReportsView: View {
    enum Page: String, CaseIterable, Identifiable {
        case spending, categories, timing, payments
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .spending: "Utgifter"
            case .categories: "Kategorier"
            case .timing: "Veckorytm"
            case .payments: "Betalningar"
            }
        }
    }

    let ledger: LedgerStore
    let userId: UserID
    var initialPage: Page = .spending
    var initialCurrency: CurrencyCode = .sek
    var groupId: GroupID?
    /// Unused now that every screen is scoped to one group — kept only so the call in
    /// `GroupSettingsView` (#151) can keep passing a no-op without this initializer changing shape.
    let onOpenGroup: (GroupID) -> Void
    let onAddExpense: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var initialized = false
    @State private var visibleLimit = 30
    @State private var page: Page = .spending
    @State private var currency: CurrencyCode = .sek
    @State private var weekOffset = 0
    @State private var selectedDay: Int?
    @State private var category: String = Categories.fallbackId
    @State private var selectedItem: ExpenseReport.Item?

    private var group: GroupState? { groupId.flatMap { ledger.state[$0] } }
    private var report: ExpenseReport {
        ExpenseReport(groups: ledger.state.groupsByLastActivity.filter { groupId == nil || $0.id == groupId })
    }
    private var days: ClosedRange<Int> { ExpenseReport.week(containing: CalendarDate(Date()), offset: weekOffset) }
    private var weekItems: [ExpenseReport.Item] { report.filtered(currency: currency, days: days) }
    private var repayments: [Payment] {
        group.map { GroupPaymentReport(group: $0, currency: currency, days: days).payments } ?? []
    }
    private var categoryItems: [ExpenseReport.Item] { report.filtered(currency: currency, category: category) }

    var body: some View {
        VStack(spacing: 0) {
            Steven.NavTitleBar(title: "Statistik", leading: .back { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Steven.UnderlineTabs(selection: $page, tabs: Page.allCases.map { (tab: $0, title: $0.title) })
                    VStack(alignment: .leading, spacing: 16) {
                        selectors
                        switch page {
                        case .spending: spending
                        case .categories: categories
                        case .timing: timing
                        case .payments: payments
                        }
                    }
                    .padding(.horizontal, StevenMetric.gutter)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .background(StevenColor.screen)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !initialized else { return }
            page = initialPage
            currency = report.currencies.contains(initialCurrency) ? initialCurrency : report.currencies[0]
            initialized = true
        }
        .onChange(of: ledger.state.appliedEventIds.count) { _, _ in
            if !report.currencies.contains(currency) { currency = report.currencies[0] }
        }
        .onChange(of: page) { _, _ in selectedDay = nil; visibleLimit = 30 }
        .onChange(of: weekOffset) { _, _ in selectedDay = nil }
        .onChange(of: currency) { _, _ in selectedDay = nil }
        .sheet(item: $selectedItem) { item in
            ExpenseDetailSheet(ledger: ledger, userId: userId, groupId: item.groupId, expenseId: item.id)
        }
    }

    // MARK: - Shared controls

    /// Currency chip ("SEK ›", 12) and the week pager, side by side where they fit.
    private var selectors: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { currencyChip; if page != .categories { datePager } }
            VStack(alignment: .leading, spacing: 8) { currencyChip; if page != .categories { datePager } }
        }
    }

    private var currencyChip: some View {
        Menu {
            ForEach(report.currencies, id: \.self) { code in
                Button(code.code) { currency = code }
            }
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: currency.code).stevenFont(.rowTitle)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(StevenColor.ink)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .frame(minHeight: StevenMetric.minimumHitTarget)
            .overlay {
                RoundedRectangle(cornerRadius: StevenMetric.controlRadius)
                    .strokeBorder(StevenColor.hairline, lineWidth: 1)
            }
        }
        .accessibilityLabel(Text("Valuta"))
    }

    private var datePager: some View {
        HStack(spacing: 4) {
            Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("Föregående vecka")
            Text(weekOffset == 0 ? String(localized: "Den här veckan") : ExpenseReport.label(for: days.lowerBound))
                .stevenFont(.footnote).lineLimit(2)
            Button { weekOffset += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(weekOffset >= 0).accessibilityLabel("Nästa vecka")
        }
        .foregroundStyle(StevenColor.ink)
    }

    // MARK: - Utgifter

    private var spending: some View {
        VStack(alignment: .leading, spacing: 16) {
            Steven.Card {
                VStack(alignment: .leading, spacing: 12) {
                    metricRow(title: String(localized: "Gemensamma utgifter"), value: total(weekItems), badge: "\(weekItems.count)")
                    metricRow(title: String(localized: "Största utgiften"),
                              value: weekItems.map(\.amountMinor).max().map(amount) ?? "—", badge: currency.code)
                    StevenWeekChart(items: weekItems, days: days, currency: currency, selectedDay: $selectedDay)
                }
            }
            expenseList(visible(weekItems, in: selectedDay.map { $0...$0 } ?? days))
            if groupId != nil {
                Button("Lägg till utgift", action: onAddExpense).buttonStyle(Steven.FilledButtonStyle())
            }
        }
    }

    // MARK: - Kategorier

    private var categories: some View {
        VStack(alignment: .leading, spacing: 16) {
            Steven.Card {
                VStack(alignment: .leading, spacing: 12) {
                    Menu {
                        ForEach(Categories.all) { option in Button(option.name) { category = option.id } }
                    } label: {
                        HStack {
                            Image(systemName: Categories.symbol(for: category))
                            Text(Categories.all.first { $0.id == category }?.name ?? category).stevenFont(.rowTitleBold)
                            Spacer()
                            Image(systemName: "chevron.down")
                        }
                        .foregroundStyle(StevenColor.ink)
                    }
                    Steven.MoneyText(amountMinor: ExpenseReport.total(categoryItems) ?? 0, currency: currency, font: .amountLarge)
                    Text("\(categoryItems.count) utgifter").stevenFont(.footnote).foregroundStyle(StevenColor.muted)
                }
            }
            expenseList(categoryItems)
        }
    }

    // MARK: - Veckorytm

    private var timing: some View {
        Steven.Card {
            VStack(alignment: .leading, spacing: 16) {
                StevenWeekDial(items: weekItems, days: days)
                datePager
                HStack {
                    Text("\(weekItems.count) utgifter").stevenFont(.footnote).foregroundStyle(StevenColor.muted)
                    Spacer()
                    Text(verbatim: currency.code).stevenFont(.footnoteBold).foregroundStyle(StevenColor.ink)
                }
            }
        }
    }

    // MARK: - Betalningar

    private var payments: some View {
        VStack(alignment: .leading, spacing: 16) {
            Steven.Card {
                VStack(alignment: .leading, spacing: 12) {
                    metricRow(title: String(localized: "Avräknade återbetalningar"),
                              value: GroupPaymentReport.total(repayments).map(amount) ?? "—", badge: "\(repayments.count)")
                    StevenWeekChart(items: [], days: days, currency: currency, payments: repayments, selectedDay: $selectedDay)
                }
            }
            if repayments.isEmpty {
                Text("Inga avräknade återbetalningar under perioden")
                    .stevenFont(.footnote).foregroundStyle(StevenColor.muted)
            } else {
                Steven.Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredRepayments.enumerated()), id: \.element.id) { index, payment in
                            PaymentStatRow(group: group, payment: payment, showsSeparator: index < filteredRepayments.count - 1)
                        }
                    }
                }
            }
            if let group {
                ShareLink(
                    item: CSVExportFile(group: group),
                    preview: SharePreview(CSVExportFile.filename(for: group))
                ) {
                    Text("Exportera CSV")
                }
                .buttonStyle(Steven.OutlineButtonStyle())
            }
        }
    }

    private var filteredRepayments: [Payment] {
        guard let selectedDay else { return repayments }
        return repayments.filter { $0.date.dayNumber == selectedDay }
    }

    // MARK: - Shared rows

    private func metricRow(title: String, value: String, badge: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).stevenFont(.footnote).foregroundStyle(StevenColor.muted)
                Text(verbatim: value).stevenFont(.amountLarge).foregroundStyle(StevenColor.ink).monospacedDigit()
            }
            Spacer(minLength: 8)
            Text(verbatim: badge).stevenFont(.footnoteBold).foregroundStyle(StevenColor.muted)
        }
    }

    private func visible(_ items: [ExpenseReport.Item], in range: ClosedRange<Int>) -> [ExpenseReport.Item] {
        items.filter { range.contains($0.date.dayNumber) }
    }

    @ViewBuilder
    private func expenseList(_ items: [ExpenseReport.Item]) -> some View {
        if items.isEmpty {
            Text("Inga utgifter under perioden").stevenFont(.footnote).foregroundStyle(StevenColor.muted)
        } else {
            Steven.Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(items.prefix(visibleLimit).enumerated()), id: \.element.id) { index, item in
                        ExpenseStatRow(item: item, showsSeparator: index < min(items.count, visibleLimit) - 1) {
                            selectedItem = item
                        }
                    }
                }
            }
            if items.count > visibleLimit {
                Button("Visa fler") { visibleLimit += 30 }.buttonStyle(Steven.OutlineButtonStyle())
            }
        }
    }

    private func total(_ entries: [ExpenseReport.Item]) -> String {
        ExpenseReport.total(entries).map(amount) ?? String(localized: "Beloppet är för stort för att visas.")
    }

    private func amount(_ minor: Int64) -> String {
        MoneyFormat.string(minor, currency, explicit: true)
    }
}

/// One row of `expenseList`: category glyph, title + day, amount — the Steven list-row idiom
/// (tonal icon, title, trailing value).
private struct ExpenseStatRow: View {
    let item: ExpenseReport.Item
    var showsSeparator = true
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                Image(systemName: Categories.symbol(for: item.categoryId))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(StevenColor.ink)
                    .frame(width: StevenMetric.iconCircle, height: StevenMetric.iconCircle)
                    .background(StevenColor.accentTint, in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).stevenFont(.rowTitle).foregroundStyle(StevenColor.ink).lineLimit(1)
                    Text(verbatim: "\(item.author) · \(ExpenseReport.label(for: item.date.dayNumber))")
                        .stevenFont(.footnote).foregroundStyle(StevenColor.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                Steven.MoneyText(amountMinor: item.amountMinor, currency: item.currency, font: .rowTitleBold)
            }
            .padding(.horizontal, StevenMetric.gutter)
            .padding(.vertical, 10)
            .frame(minHeight: StevenMetric.rowHeight)
            .contentShape(.rect)
            .overlay(alignment: .bottom) {
                if showsSeparator { Steven.Hairline(color: StevenColor.rowSeparator) }
            }
        }
        .buttonStyle(Steven.RowButtonStyle())
        .accessibilityElement(children: .combine)
    }
}

/// A settled/pending/disputed repayment in the Betalningar tab, same idiom as `ExpenseStatRow`.
private struct PaymentStatRow: View {
    let group: GroupState?
    let payment: Payment
    var showsSeparator = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(StevenColor.ink)
                .frame(width: StevenMetric.iconCircle, height: StevenMetric.iconCircle)
                .background(StevenColor.accentTint, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(name(payment.fromMemberId)) → \(name(payment.toMemberId))")
                    .stevenFont(.rowTitle).foregroundStyle(StevenColor.ink).lineLimit(1)
                Text(verbatim: "\(ExpenseReport.label(for: payment.date.dayNumber)) · \(status)")
                    .stevenFont(.footnote).foregroundStyle(StevenColor.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            Steven.MoneyText(amountMinor: payment.amountMinor, currency: payment.currency, font: .rowTitleBold)
        }
        .padding(.horizontal, StevenMetric.gutter)
        .padding(.vertical, 10)
        .frame(minHeight: StevenMetric.rowHeight)
        .overlay(alignment: .bottom) {
            if showsSeparator { Steven.Hairline(color: StevenColor.rowSeparator) }
        }
        .accessibilityElement(children: .combine)
    }

    private func name(_ memberId: MemberID) -> String { group?.members[memberId]?.displayName ?? "?" }
    private var status: String {
        if payment.countsTowardBalances(asOf: CalendarDate(Date())) { return String(localized: "Avräknad") }
        return payment.status == .disputed ? String(localized: "Bestriden") : String(localized: "Väntar på bekräftelse")
    }
}

/// The week bar chart (08/12's accent/coral), moved here from the old `GroupSpendingView` and
/// restyled: `StevenColor.owe` bars, the selected day in `accentFill`, a money badge on top of it.
private struct StevenWeekChart: View {
    let items: [ExpenseReport.Item]
    let days: ClosedRange<Int>
    let currency: CurrencyCode
    var payments: [Payment]? = nil
    @Binding var selectedDay: Int?

    private var points: [(day: Int, total: Int64?)] {
        days.map { day in
            if let payments {
                return (day, GroupPaymentReport.total(payments.filter { $0.date.dayNumber == day }))
            }
            return (day, ExpenseReport.total(items.filter { $0.date.dayNumber == day }))
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Chart {
                ForEach(points, id: \.day) { point in
                    if let total = point.total {
                        BarMark(x: .value("Dag", point.day), y: .value("Belopp", total), width: .fixed(24))
                            .foregroundStyle(selectedDay == point.day ? StevenColor.accentFill : StevenColor.owe)
                            .cornerRadius(6)
                            .annotation(position: .top) {
                                if selectedDay == point.day {
                                    Text(verbatim: MoneyFormat.string(total, currency, explicit: true))
                                        .stevenFont(.footnoteBold)
                                        .foregroundStyle(StevenColor.ink)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(StevenColor.accentTint, in: .capsule)
                                }
                            }
                    }
                }
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartXScale(domain: (days.lowerBound - 1)...(days.upperBound + 1))
            .chartYScale(domain: 0...max(points.compactMap(\.total).max() ?? 0, 1))
            .frame(height: 160)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(payments == nil ? String(localized: "Utgifter per dag, \(currency.code)") : String(localized: "Återbetalningar per dag, \(currency.code)"))
            .accessibilityValue(points.map { "\(ExpenseReport.label(for: $0.day)): \(amount($0.total))" }.joined(separator: "; "))
            HStack(spacing: 4) {
                ForEach(Array(days), id: \.self) { day in
                    Button { selectedDay = selectedDay == day ? nil : day } label: {
                        Text(ExpenseReport.dayLabel(day))
                            .stevenFont(.footnote).foregroundStyle(StevenColor.muted)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.plain)
                }
            }
            if points.contains(where: { $0.total == nil }) {
                Text("Beloppet är för stort för att visas.").stevenFont(.footnote).foregroundStyle(StevenColor.muted)
            }
        }
    }

    private func amount(_ minor: Int64?) -> String {
        minor.map { MoneyFormat.string($0, currency, explicit: true) } ?? "—"
    }
}

/// Veckorytm's circular day dial, restyled from `WeeklyActivityDial`: `StevenColor.surface` disc,
/// `StevenColor.owe` ring segments, ink ticks and centre count.
private struct StevenWeekDial: View {
    let items: [ExpenseReport.Item]
    let days: ClosedRange<Int>
    @ScaledMetric private var diameter: CGFloat = 270

    var body: some View {
        ZStack {
            ForEach(0..<28, id: \.self) { tick in
                Capsule().fill(StevenColor.hairline.opacity(tick % 4 == 0 ? 1 : 0.6))
                    .frame(width: tick % 4 == 0 ? 2 : 1, height: tick % 4 == 0 ? 12 : 6)
                    .offset(y: -min(diameter, 320) / 2 + 22)
                    .rotationEffect(.degrees(Double(tick) * 360 / 28))
            }
            ForEach(0..<7, id: \.self) { offset in
                let count = items.filter { $0.date.dayNumber == days.lowerBound + offset }.count
                let fraction = items.isEmpty ? 0 : Double(count) / Double(items.count)
                Circle().trim(from: Double(offset) / 7, to: Double(offset) / 7 + fraction / 7 * 0.85)
                    .stroke(StevenColor.owe, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(56)
                Text(ExpenseReport.dayLabel(days.lowerBound + offset))
                    .stevenFont(.footnoteBold).foregroundStyle(StevenColor.ink)
                    .rotationEffect(.degrees(-Double(offset) * 360 / 7))
                    .offset(y: -min(diameter, 320) / 2 + 44)
                    .rotationEffect(.degrees(Double(offset) * 360 / 7))
            }
            VStack(spacing: 2) {
                Text(verbatim: "\(items.count)").stevenFont(.amountHero).monospacedDigit()
                Text("utgifter").stevenFont(.footnote)
            }.foregroundStyle(StevenColor.ink)
        }
        .frame(width: min(diameter, 320), height: min(diameter, 320))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Antal utgifter per veckodag")
        .accessibilityValue(Array(days).map { day in "\(ExpenseReport.dayLabel(day)): \(items.filter { $0.date.dayNumber == day }.count)" }.joined(separator: "; "))
    }
}
