import SwiftUI
import KvittaCore
import KvittaStorage

/// The glanceable home: one answer about the user's position, followed by the latest activity.
struct OverviewView: View {
    let ledger: LedgerStore
    let userId: UserID
    let profile: UserProfile
    let onShowActivity: () -> Void
    let onProfile: () -> Void
    let onOpenActivity: (FeedEntry) -> Void
    let onShowPosition: () -> Void
    let onOpenGroup: (GroupID) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(title: "Översikt", profile: profile, onProfile: onProfile, showsBrand: true)

                if horizontalSizeClass == .regular {
                    HStack(alignment: .top, spacing: 24) {
                        overviewBalances
                        overviewSections
                    }
                } else {
                    overviewBalances
                    overviewSections
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(AmbientBackground())
        .navigationBarHidden(true)
    }

    private var overviewSections: some View {
        VStack(alignment: .leading, spacing: 24) {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                activityHeader
                recentActivity
            }
            Divider()
            relevantGroup
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var overviewBalances: some View {
        let groups = ledger.state.groupsByLastActivity
        let book = BalanceBook(groups: groups.map { group in
            BalanceBook.GroupSlice(name: group.name, balances: group.balances(), members: group.members)
        })
        let ordered = book.summariesForDisplay(userId: userId)
        let summaries = ordered.isEmpty
            ? [BalanceBook.Summary(currency: .sek, receivableMinor: 0, payableMinor: 0)] : ordered
        return VStack(spacing: 12) {
            ForEach(Array(summaries.enumerated()), id: \.element.currency) { index, summary in
                Button(action: onShowPosition) {
                    if index == 0 { BalanceHero(summary: summary) }
                    else { CompactCurrencyBalance(summary: summary) }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Öppnar Ställning")
            }
        }
    }

    private struct CompactCurrencyBalance: View {
        let summary: BalanceBook.Summary

        var body: some View {
            // An open currency deserves the same directional meaning as the leading one.
            if summary.hasOpenBalances {
                BalanceHero(summary: summary)
            } else {
                HStack(spacing: 12) {
                    Text("Kvitt i \(summary.currency.code)")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                    Spacer()
                    Image(systemName: "checkmark").foregroundStyle(Theme.secondary).accessibilityHidden(true)
                }
                .padding(.horizontal, 4)
                .frame(minHeight: 44)
            }
        }
    }

    private var activityHeader: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout())
        return layout {
            Text("Senaste aktivitet")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Visa alla", action: onShowActivity)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44)
        }
    }

    private var recentActivity: some View {
        let entries = Array(FeedEntry.build(from: ledger.state, userId: userId).prefix(4))
        return VStack(spacing: 0) {
            if entries.isEmpty {
                Text("Utgifter och betalningar dyker upp här.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(entries) { entry in
                    Button { onOpenActivity(entry) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: entry.kind.isPayment ? "arrow.left.arrow.right" : "receipt")
                            .foregroundStyle(Theme.secondary)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text(entry.subtitle).font(.caption).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        NeutralAmountText(amountMinor: entry.amountMinor, currency: entry.currency, size: 15, explicit: entry.explicit)
                    }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 12)
                    if entry.id != entries.last?.id { Divider().padding(.leading, 40) }
                }
            }
        }
    }

    private var relevantGroup: some View {
        let group = ledger.state.groupsByLastActivity.first
        return Group {
            if let group {
                Button { onOpenGroup(group.id) } label: {
                    HStack(spacing: 12) {
                        GroupBadge(name: group.name, size: 40, groupId: group.id)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Senast aktiv i").font(.caption).foregroundStyle(Theme.secondary)
                            Text(GroupBadge.title(of: group.name)).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text("\(String(localized: "\(group.activeMembers.count) personer")) · \(String(localized: "\(group.visibleExpenses.count) utgifter"))")
                                .font(.caption).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Börja dela tillsammans").font(.headline.weight(.bold)).foregroundStyle(Theme.ink)
                    Text("Skapa en grupp och lägg till din första utgift.").font(.subheadline).foregroundStyle(Theme.secondary)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private extension FeedEntry.Kind {
    var isPayment: Bool {
        if case .payment = self { return true }
        return false
    }
}
