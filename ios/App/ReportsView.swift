import SwiftUI
import KvittaCore
import KvittaStorage

struct ReportDestination: Identifiable {
    let id = UUID()
    let page: ReportsView.Page
    let currency: CurrencyCode
    let groupId: GroupID?
}

struct ReportsView: View {
    enum Page: String, CaseIterable, Identifiable {
        case reports, spending, categories, timing, activity
        var id: String { rawValue }
    }
    let ledger: LedgerStore
    let userId: UserID
    var initialPage: Page = .reports
    var initialCurrency: CurrencyCode = .sek
    var groupId: GroupID?
    let onOpenGroup: (GroupID) -> Void
    let onAddExpense: () -> Void
    @State private var activityKind = 0
    @State private var initialized = false
    @State private var visibleLimit = 30
    @Environment(\.dismiss) private var dismiss
    @State private var page: Page = .reports
    @State private var currency: CurrencyCode = .sek
    @State private var weekOffset = 0
    @State private var selectedDay: Int?
    @State private var category: String = "restaurang"
    @State private var query = ""
    @State private var selectedItem: ExpenseReport.Item?

    private var report: ExpenseReport {
        ExpenseReport(groups: ledger.state.groupsByLastActivity.filter { groupId == nil || $0.id == groupId })
    }
    private var activityEntries: [FeedEntry] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return FeedEntry.build(from: ledger.state, userId: userId, scope: .allActivity).filter { entry in
            let isPayment = entry.paymentStatus != nil
            return entry.currency == currency && (groupId == nil || entry.groupId == groupId)
                && (activityKind == 0 || (activityKind == 1 && !isPayment) || (activityKind == 2 && isPayment))
                && (search.isEmpty || (entry.title + " " + entry.subtitle).localizedCaseInsensitiveContains(search))
        }
    }
    private var days: ClosedRange<Int> { ExpenseReport.week(containing: CalendarDate(Date()), offset: weekOffset) }
    private var items: [ExpenseReport.Item] { report.filtered(currency: currency, days: days) }
    private var visible: [ExpenseReport.Item] {
        report.filtered(currency: currency,
                        days: page == .activity ? nil : selectedDay.map { $0...$0 } ?? days,
                        category: page == .categories ? category : nil, search: query)
    }
    private var surface: Color { page == .reports || page == .timing ? Editorial.mint : page == .categories ? Editorial.purple : Editorial.coal }
    private var isLight: Bool { page != .spending && page != .activity }
    private var heading: String {
        switch page {
        case .reports: String(localized: "Rapporter")
        case .spending: String(localized: "Utgifter")
        case .categories: String(localized: "Kategorier")
        case .timing: String(localized: "Veckorytm")
        case .activity: String(localized: "Aktivitet")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                EditorialHeading(title: heading, dark: isLight, onBack: { dismiss() })
                if let groupId, let group = ledger.state[groupId] {
                    Text(GroupBadge.title(of: group.name)).font(.caption)
                        .foregroundStyle(isLight ? Editorial.coal : Editorial.muted)
                }
                pageControls
                if page != .activity && page != .timing { periodControls }
                if page == .timing { currencyMenu }
                switch page {
                case .reports: reportCover
                case .spending: spending
                case .categories: categoryStack
                case .timing: timing
                case .activity: activity
                }
                if page != .activity {
                    Text("\(visible.count) utgifter").font(.caption.weight(.semibold))
                        .foregroundStyle(isLight ? Editorial.coal : Editorial.muted)
                    ForEach(visible.prefix(visibleLimit)) { item in
                        EditorialExpenseRow(item: item, dark: isLight) { selectedItem = item }
                    }
                    if visible.count > visibleLimit {
                        EditorialPill(title: String(localized: "Visa fler")) { visibleLimit += 30 }
                    }
                    if visible.isEmpty {
                        Text("Inga utgifter under perioden")
                            .font(.subheadline).foregroundStyle(isLight ? Editorial.coal : Editorial.muted)
                    }
                }
            }.padding(20).padding(.bottom, 32)
        }
        .background(surface.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if page == .activity {
                searchField.padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Editorial.coal)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .tint(Editorial.coal)
        .onAppear {
            guard !initialized else { return }
            page = initialPage; currency = report.currencies.contains(initialCurrency) ? initialCurrency : report.currencies[0]; initialized = true
        }
        .onChange(of: ledger.state.appliedEventIds.count) { _, _ in
            if !report.currencies.contains(currency) { currency = report.currencies[0] }
        }
        .onChange(of: weekOffset) { _, _ in selectedDay = nil }
        .onChange(of: currency) { _, _ in selectedDay = nil }
        .sheet(item: $selectedItem) { item in
            ExpenseDetailSheet(ledger: ledger, userId: userId, groupId: item.groupId, expenseId: item.id)
        }
    }

    private var pageControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Page.allCases, id: \.self) { destination in
                    EditorialPill(title: title(destination), selected: page == destination) {
                        page = destination; selectedDay = nil; query = ""; visibleLimit = 30
                    }
                }
            }
        }
    }

    private func title(_ page: Page) -> String {
        switch page {
        case .reports: String(localized: "Översikt")
        case .spending: String(localized: "Utgifter")
        case .categories: String(localized: "Kategorier")
        case .timing: String(localized: "Veckorytm")
        case .activity: String(localized: "Aktivitet")
        }
    }

    private var periodControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { currencyMenu; datePager }
            VStack(alignment: .leading, spacing: 8) { currencyMenu; datePager }
        }
    }

    private var currencyMenu: some View {
        Menu {
            ForEach(report.currencies, id: \.self) { code in
                Button(code.code) { currency = code }
            }
        } label: {
            Label(currency.code, systemImage: "chevron.down")
                .font(.caption.weight(.semibold)).foregroundStyle(Editorial.coal)
                .padding(.horizontal, 16).frame(minHeight: 44).background(Editorial.paper, in: .capsule)
        }.accessibilityLabel("Valuta")
    }

    private var datePager: some View {
        HStack(spacing: 4) {
            Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .accessibilityLabel("Föregående vecka")
            Text(weekOffset == 0 ? String(localized: "Den här veckan") : ExpenseReport.label(for: days.lowerBound))
                .font(.caption.weight(.medium)).lineLimit(2)
            Button { weekOffset += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(weekOffset >= 0).accessibilityLabel("Nästa vecka")
        }.foregroundStyle(Editorial.coal).background(Editorial.paper, in: .capsule)
    }

    private var reportCover: some View {
        VStack(spacing: 0) {
            Image("ReportCover").resizable().scaledToFit().frame(maxHeight: 280)
                .accessibilityHidden(true)
            EditorialPanel(fill: Editorial.coal) {
                VStack(alignment: .leading, spacing: 18) {
                    searchField
                    Text("DIN VECKA").font(Editorial.heading(20)).foregroundStyle(Editorial.paper)
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "chart.bar.xaxis").font(.title3)
                            .foregroundStyle(Editorial.coal).frame(width: 44, height: 44)
                            .background(Editorial.coral, in: .circle)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Gemensamma utgifter").font(.subheadline).foregroundStyle(Editorial.muted)
                            Text(total(items)).font(Editorial.heading(32)).foregroundStyle(Editorial.paper).monospacedDigit()
                            Text("\(items.count) utgifter").font(.caption).foregroundStyle(Editorial.muted)
                        }
                        Spacer(minLength: 0)
                        EditorialCircleButton(symbol: "arrow.up.right", label: String(localized: "Visa rapport")) { page = .spending }
                    }
                    HStack {
                        Text("SLICE / RAPPORTER").font(.caption2.weight(.semibold)).foregroundStyle(Editorial.muted)
                        Spacer()
                        EditorialCircleButton(symbol: "plus", label: String(localized: "Lägg till utgift"), fill: Editorial.yellow, action: onAddExpense)
                    }
                }
            }
        }
    }

    private var spending: some View {
        EditorialPanel(fill: Editorial.coral, padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                EditorialMetric(title: String(localized: "Gemensamma utgifter"), value: total(items), badge: "\(items.count)")
                EditorialMetric(title: String(localized: "Största utgiften"), value: items.max(by: { $0.amountMinor < $1.amountMinor }).map { MoneyFormat.string($0.amountMinor, currency, explicit: true) } ?? "—", badge: currency.code)
                EditorialWeekChart(items: items, days: days, currency: currency, selectedDay: $selectedDay)
            }
        }
    }

    private var categoryStack: some View {
        EditorialCardStack {
            Menu {
                ForEach(Categories.all) { option in Button(option.name) { category = option.id } }
            } label: {
                HStack { Text("Välj kategori"); Spacer(); Image(systemName: "chevron.down") }
            }
        } metadata: {
            HStack {
                Text("\(visible.count) utgifter").font(Editorial.heading(18))
                Spacer()
                Text(currency.code).font(.caption)
            }
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                EditorialCardTitle(title: Categories.all.first(where: { $0.id == category })?.name ?? category,
                                    symbol: Categories.symbol(for: category))
                EditorialMetadataPill(text: total(visible))
                Image("SharedDinner").resizable().scaledToFit().frame(maxHeight: 330).accessibilityHidden(true)
                HStack {
                    Text("GEMENSAMT / \(currency.code)").font(.caption2.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.down")
                }.foregroundStyle(Editorial.coal)
            }
        }
    }

    private var timing: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("NÄR NI DELAR\nPÅ VARDAGEN").font(Editorial.heading(38)).foregroundStyle(Editorial.coal)
            WeeklyActivityDial(items: items, days: days)
            datePager
            Text("Antal utgifter per veckodag").font(.subheadline).foregroundStyle(Editorial.coal)
            HStack {
                EditorialBadge(text: String(localized: "\(items.count) utgifter"))
                Spacer()
                Text(currency.code).font(.caption.weight(.medium)).foregroundStyle(Editorial.coal)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Button { page = .activity } label: {
                Image(systemName: "magnifyingglass").foregroundStyle(Editorial.coal)
                    .frame(width: 44, height: 44).background(Editorial.coral, in: .circle)
            }.accessibilityLabel("Sök utgifter")
            TextField("Sök utgifter", text: $query, prompt: Text("Sök utgifter").foregroundStyle(Editorial.muted))
                .font(.subheadline).foregroundStyle(Editorial.paper)
                .submitLabel(.search)
                .onSubmit { page = .activity }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                    .foregroundStyle(Editorial.paper).accessibilityLabel("Rensa sökning")
            }
        }.padding(.horizontal, 14).frame(minHeight: 48).background(Editorial.raised, in: .capsule)
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 20) {
            currencyMenu
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "asterisk").foregroundStyle(Editorial.coal)
                    .frame(width: 30, height: 30).background(Editorial.yellow, in: .circle)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Utgifter & betalningar").font(.headline).foregroundStyle(Editorial.paper)
                    Text("Sök i det ni har lagt till. Tryck på en post för detaljer.")
                        .font(.subheadline).foregroundStyle(Editorial.muted)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack { Spacer(minLength: 0); activityFilters }
                ScrollView(.horizontal, showsIndicators: false) { activityFilters }
            }
            ForEach(activityEntries.prefix(visibleLimit)) { entry in
                Button {
                    if entry.paymentStatus != nil { onOpenGroup(entry.groupId) }
                    else { selectedItem = report.items.first { $0.id.rawValue == entry.id } }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.title).font(.headline)
                        Text(MoneyFormat.string(entry.amountMinor, entry.currency, explicit: true))
                            .font(Editorial.heading(26)).monospacedDigit()
                        Text(entry.subtitle).font(.caption)
                        Text(entry.timestamp.date, style: .date).font(.caption2)
                        if let item = report.items.first(where: { $0.id.rawValue == entry.id }) {
                            Text("Registrerat av \(item.author)").font(.caption2)
                        }
                        if entry.wasEdited { Text("redigerad").font(.caption2) }
                        if entry.paymentStatus == .pending { Text("väntar").font(.caption.weight(.semibold)) }
                        if entry.paymentStatus == .disputed { Text("bestriden").font(.caption.weight(.semibold)) }
                    }.foregroundStyle(Editorial.coal).padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(entry.paymentStatus == nil ? Editorial.mint : Editorial.paper, in: .rect(cornerRadius: 24))
                }.buttonStyle(.plain)
            }
            if activityEntries.count > visibleLimit {
                EditorialPill(title: String(localized: "Visa fler")) { visibleLimit += 30 }
            }
            if activityEntries.isEmpty { Text("Inga matchande poster").foregroundStyle(Editorial.muted) }
        }
    }

    private var activityFilters: some View {
        HStack(spacing: 8) {
            EditorialPill(title: String(localized: "Alla"), selected: activityKind == 0) { activityKind = 0 }
            EditorialPill(title: String(localized: "Utgifter"), selected: activityKind == 1) { activityKind = 1 }
            EditorialPill(title: String(localized: "Betalningar"), selected: activityKind == 2) { activityKind = 2 }
        }.fixedSize(horizontal: true, vertical: false)
    }

    private func total(_ entries: [ExpenseReport.Item]) -> String {
        ExpenseReport.total(entries).map { MoneyFormat.string($0, currency, explicit: true) } ?? String(localized: "Beloppet är för stort för att visas.")
    }
}

struct WeeklyActivityDial: View {
    let items: [ExpenseReport.Item]
    let days: ClosedRange<Int>
    @ScaledMetric private var diameter: CGFloat = 270

    var body: some View {
        ZStack {
            Circle().fill(Editorial.paper)
            ForEach(0..<28) { tick in
                Capsule().fill(Editorial.coal.opacity(tick % 4 == 0 ? 0.8 : 0.25))
                    .frame(width: tick % 4 == 0 ? 2 : 1, height: tick % 4 == 0 ? 12 : 6)
                    .offset(y: -min(diameter, 320) / 2 + 22)
                    .rotationEffect(.degrees(Double(tick) * 360 / 28))
            }
            ForEach(0..<7) { offset in
                let count = items.filter { $0.date.dayNumber == days.lowerBound + offset }.count
                let fraction = items.isEmpty ? 0 : Double(count) / Double(items.count)
                Circle().trim(from: Double(offset) / 7, to: Double(offset) / 7 + fraction / 7 * 0.85)
                    .stroke(Editorial.coral, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(56)
                Text(ExpenseReport.dayLabel(days.lowerBound + offset))
                    .font(.caption2.weight(.semibold)).foregroundStyle(Editorial.coal)
                    .rotationEffect(.degrees(-Double(offset) * 360 / 7))
                    .offset(y: -min(diameter, 320) / 2 + 44)
                    .rotationEffect(.degrees(Double(offset) * 360 / 7))
            }
            VStack(spacing: 2) {
                Text("\(items.count)").font(Editorial.heading(42))
                Text("utgifter").font(.caption)
            }.foregroundStyle(Editorial.coal)
        }
        .frame(width: min(diameter, 320), height: min(diameter, 320))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Antal utgifter per veckodag")
        .accessibilityValue(Array(days).map { day in "\(ExpenseReport.dayLabel(day)): \(items.filter { $0.date.dayNumber == day }.count)" }.joined(separator: "; "))
    }
}
