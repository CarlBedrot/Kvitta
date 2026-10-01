import SwiftUI
import KvittaCore
import KvittaStorage

/// The reference dashboard, backed by the same balances and settlement routes as Position.
struct OverviewView: View {
    let ledger: LedgerStore
    let userId: UserID
    let profile: UserProfile
    let onShowActivity: () -> Void
    let onProfile: () -> Void
    let onOpenActivity: (FeedEntry) -> Void
    let onSettle: (SuggestedTransfer, GroupID) -> Void
    let onShowPosition: () -> Void
    let onOpenGroup: (GroupID) -> Void
    let onReport: (ReportDestination) -> Void
    @State private var currency: CurrencyCode = .sek
    @State private var selectedDay: Int?
    @State private var selectedGroup: GroupID?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var groups: [GroupState] { ledger.state.groupsByLastActivity }
    private var report: ExpenseReport {
        ExpenseReport(groups: groups.filter { selectedGroup == nil || $0.id == selectedGroup })
    }
    private var days: ClosedRange<Int> { ExpenseReport.week(containing: CalendarDate(Date())) }
    private var weekItems: [ExpenseReport.Item] { report.filtered(currency: currency, days: days) }
    private var recent: [FeedEntry] {
        FeedEntry.build(from: ledger.state, userId: userId, scope: .allActivity).filter { entry in
            entry.currency == currency && (selectedGroup == nil || entry.groupId == selectedGroup)
                && (selectedDay == nil || (entry.paymentStatus == nil
                    ? report.items.first { $0.id.rawValue == entry.id }?.date.dayNumber == selectedDay
                    : CalendarDate(entry.timestamp.date).dayNumber == selectedDay))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                identity
                selectors
                balances
                EditorialPanel(fill: Editorial.purple) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            Text("VECKANS\nUTGIFTER").font(Editorial.heading(30))
                            Spacer()
                            EditorialCircleButton(symbol: "arrow.up.right", label: String(localized: "Visa rapport")) { onReport(ReportDestination(page: .spending, currency: currency, groupId: selectedGroup)) }
                        }.foregroundStyle(Editorial.coal)
                        Text(ExpenseReport.total(weekItems).map { MoneyFormat.string($0, currency, explicit: true) } ?? "—")
                            .font(Editorial.heading(34)).monospacedDigit().foregroundStyle(Editorial.coal)
                        EditorialWeekChart(items: weekItems, days: days, currency: currency, area: true, selectedDay: $selectedDay)
                    }
                }
                HStack {
                    Text("Senaste aktivitet").textCase(.uppercase).font(Editorial.heading(22)).foregroundStyle(Editorial.paper)
                    Spacer()
                    EditorialCircleButton(symbol: "arrow.up.right", label: String(localized: "Aktivitet")) { onReport(ReportDestination(page: .activity, currency: currency, groupId: selectedGroup)) }
                }
                if recent.isEmpty {
                    Text("Inga matchande utgifter").font(.subheadline).foregroundStyle(Editorial.muted).padding(.vertical, 8)
                }
                ForEach(recent.prefix(3)) { item in
                    EditorialActivityRow(entry: item) { onOpenActivity(item) }
                }
                reportLinks
                if let group = groups.first {
                    Button { onOpenGroup(group.id) } label: {
                        HStack(spacing: 12) {
                            GroupBadge(name: group.name, size: 40, groupId: group.id)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Senast aktiv i").font(.caption).foregroundStyle(Editorial.muted)
                                Text(GroupBadge.title(of: group.name)).font(.headline).foregroundStyle(Editorial.paper)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").foregroundStyle(Editorial.paper)
                        }.padding(.vertical, 12)
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
        }
        .background(Editorial.coal.ignoresSafeArea())
        .navigationBarHidden(true)
        .onAppear { reconcileSelection() }
        .onChange(of: ledger.state.appliedEventIds.count) { _, _ in reconcileSelection() }
        .onChange(of: currency) { _, _ in selectedDay = nil }
        .onChange(of: selectedGroup) { _, _ in
            if !report.currencies.contains(currency) { currency = report.currencies[0] }
            selectedDay = nil
        }
    }

    private func reconcileSelection() {
        if let selectedGroup, !groups.contains(where: { $0.id == selectedGroup }) { self.selectedGroup = nil }
        if !report.currencies.contains(currency) { currency = report.currencies[0] }
    }

    private var identity: some View {
        HStack(spacing: 10) {
            SliceMark(size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("slice").font(.title3.weight(.bold)).foregroundStyle(Editorial.paper)
                Text(profile.nameOrDefault).font(.caption).foregroundStyle(Editorial.muted)
            }
            Spacer()
            EditorialCircleButton(symbol: "bell", label: String(localized: "Aktivitet"), action: onShowActivity)
            Button(action: onProfile) {
                Avatar(name: profile.nameOrDefault, photo: profile.avatarData, size: 44)
            }.buttonStyle(.plain).accessibilityLabel("Profil")
        }
    }

    private var selectors: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Menu {
                Button("Alla grupper") { selectedGroup = nil }
                ForEach(groups) { group in Button(GroupBadge.title(of: group.name)) { selectedGroup = group.id } }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.2")
                    Text(groups.first(where: { $0.id == selectedGroup }).map { GroupBadge.title(of: $0.name) } ?? String(localized: "Alla grupper"))
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                }.font(.subheadline).foregroundStyle(Editorial.coal).padding(.horizontal, 16)
                    .frame(minHeight: 44).background(Editorial.paper, in: .capsule)
            }
            Menu {
                ForEach(report.currencies, id: \.self) { code in Button(code.code) { currency = code } }
            } label: {
                Text(currency.code).font(.subheadline.weight(.semibold)).foregroundStyle(Editorial.coal)
                    .padding(.horizontal, 16).frame(minHeight: 44).background(Editorial.paper, in: .capsule)
            }.accessibilityLabel("Valuta")
        }
    }

    private var balances: some View {
        let book = BalanceBook(groups: groups.map {
            BalanceBook.GroupSlice(name: $0.name, balances: $0.balances(), members: $0.members)
        })
        let summaries = book.summariesForDisplay(userId: userId)
        return EditorialPanel(fill: Editorial.raised, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Editorial.coal).frame(width: 40, height: 40)
                        .background(Editorial.yellow, in: .rect(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DIN STÄLLNING").font(Editorial.heading(20)).foregroundStyle(Editorial.paper)
                        if summaries.isEmpty || !summaries.contains(where: \.hasOpenBalances) {
                            Text("Alla är kvitt").font(.subheadline).foregroundStyle(Editorial.muted)
                        }
                        ForEach(summaries.filter(\.hasOpenBalances), id: \.currency) { summary in
                            if summary.payableMinor > 0 {
                                balanceLine(String(localized: "Du är skyldig"), summary.payableMinor, summary.currency)
                            }
                            if summary.receivableMinor > 0 {
                                balanceLine(String(localized: "Du ska få"), summary.receivableMinor, summary.currency)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    EditorialCircleButton(symbol: "arrow.up.right", label: String(localized: "Ställning"), action: onShowPosition)
                }
                ForEach(groups) { group in
                    if let me = group.me(for: userId) {
                        ForEach(group.suggestedTransfers().filter { $0.from == me.id }, id: \.self) { transfer in
                            Button { onSettle(transfer, group.id) } label: {
                                ViewThatFits(in: .horizontal) {
                                    HStack {
                                        Text("Betala \(group.members[transfer.to]?.displayName ?? "?")")
                                        Spacer(minLength: 4)
                                        Text(MoneyFormat.string(transfer.amountMinor, transfer.currency, explicit: true))
                                        Image(systemName: "arrow.up.right")
                                    }
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Betala \(group.members[transfer.to]?.displayName ?? "?")")
                                        Text(MoneyFormat.string(transfer.amountMinor, transfer.currency, explicit: true))
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Editorial.coal)
                                .padding(14).background(Editorial.mint, in: .rect(cornerRadius: 18))
                            }.buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityHint(GroupBadge.title(of: group.name))
                        }
                    }
                }
            }
        }
    }

    private func balanceLine(_ title: String, _ amount: Int64, _ currency: CurrencyCode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Editorial.muted)
            Text(MoneyFormat.string(amount, currency, explicit: true))
                .font(.headline).monospacedDigit().foregroundStyle(Editorial.paper)
        }
        .accessibilityElement(children: .combine)
    }

    private var reportLinks: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                EditorialPill(title: String(localized: "Rapporter"), fill: Editorial.mint) { onReport(ReportDestination(page: .reports, currency: currency, groupId: selectedGroup)) }
                EditorialPill(title: String(localized: "Kategorier"), fill: Editorial.yellow) { onReport(ReportDestination(page: .categories, currency: currency, groupId: selectedGroup)) }
                EditorialPill(title: String(localized: "Veckorytm"), fill: Editorial.paper) { onReport(ReportDestination(page: .timing, currency: currency, groupId: selectedGroup)) }
            }
        }
    }
}
