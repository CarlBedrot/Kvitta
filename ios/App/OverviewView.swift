import SwiftUI
import KvittaCore
import KvittaStorage

/// The glanceable home: one answer about the user's position, followed by the latest activity.
struct OverviewView: View {
    let ledger: LedgerStore
    let userId: UserID
    let profile: UserProfile
    let onAddExpense: () -> Void
    let onShowActivity: () -> Void
    let onProfile: () -> Void
    let onOpenActivity: (FeedEntry) -> Void
    let onShowPosition: () -> Void
    let onOpenGroup: (GroupID) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Översikt", subtitle: "Delat och klart.", profile: profile, onProfile: onProfile, showGreeting: true)

                if horizontalSizeClass == .regular {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(spacing: 16) {
                            overviewCard
                            addExpenseButton
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            activityHeader
                            recentActivity
                            relevantGroup
                        }
                    }
                } else {
                    overviewCard
                    addExpenseButton
                    activityHeader
                    recentActivity
                    relevantGroup
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 130)
        }
        .background(AmbientBackground())
        .navigationBarHidden(true)
    }

    private var overviewCard: some View {
        let groups = ledger.state.groupsByLastActivity
        let book = BalanceBook(groups: groups.map { group in
            BalanceBook.GroupSlice(name: group.name, balances: group.balances(), members: group.members)
        })
        let currencies = book.currencies.isEmpty ? [.sek] : book.currencies
        return VStack(spacing: 12) {
            ForEach(Array(currencies.enumerated()), id: \.element) { index, currency in
                Button(action: onShowPosition) {
                    if index == 0 {
                        BalanceHero(summary: book.summary(for: currency, userId: userId),
                                    label: currencies.count == 1 ? "Din ställning" : "Din ställning · \(currency.code)",
                                    explanation: "Totalt mellan dig och vänner · \(currency.code)")
                    } else {
                        CompactCurrencyBalance(summary: book.summary(for: currency, userId: userId))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Din ställning i \(currency.code)")
                .accessibilityValue(MoneyFormat.string(book.summary(for: currency, userId: userId).netMinor, currency, sign: .always, explicit: true))
                .accessibilityHint("Öppnar Ställning")
            }
        }
    }

    private struct CompactCurrencyBalance: View {
        let summary: BalanceBook.Summary

        var body: some View {
            HStack(spacing: 14) {
                Text(summary.currency.code)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 42, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.hasOpenBalances ? MoneyFormat.string(summary.netMinor, summary.currency, sign: .always) : String(localized: "Allt är jämnt"))
                        .font(.title3.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                    Text("Öppna saldon i valutan")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 1))
        }
    }

    private var addExpenseButton: some View {
        Button(action: onAddExpense) {
            Label("Lägg till utgift", systemImage: "plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
    }

    private var activityHeader: some View {
        HStack {
            Text("Senaste aktivitet")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button("Visa alla", action: onShowActivity)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondary)
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
                    .padding(18)
            } else {
                ForEach(entries) { entry in
                    Button { onOpenActivity(entry) } label: {
                    HStack(spacing: 12) {
                        IconBadge(systemImage: entry.kind.isPayment ? "arrow.left.arrow.right" : "receipt", tint: entry.kind.isPayment ? Theme.positive : Theme.pizzaOrange, size: 38)
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
                    if entry.id != entries.last?.id { Divider().padding(.leading, 50) }
                }
            }
        }
        .padding(.horizontal, 16)
        .background(Theme.card, in: .rect(cornerRadius: 24))
    }

    private var relevantGroup: some View {
        let group = ledger.state.groupsByLastActivity.first
        return Group {
            if let group {
                Button { onOpenGroup(group.id) } label: {
                    HStack(spacing: 12) {
                        GroupBadge(name: group.name, size: 48, groupId: group.id)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Senast aktiv i").font(.caption).foregroundStyle(Theme.secondary)
                            Text(GroupBadge.title(of: group.name)).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text("\(String(localized: "\(group.activeMembers.count) personer")) · \(String(localized: "\(group.visibleExpenses.count) utgifter"))")
                                .font(.caption).foregroundStyle(Theme.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
                    }
                    .padding(16)
                    .background(Theme.card, in: .rect(cornerRadius: 22))
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Börja dela tillsammans").font(.headline.weight(.bold)).foregroundStyle(Theme.ink)
                    Text("Skapa en grupp och lägg till din första utgift.").font(.subheadline).foregroundStyle(Theme.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accentSubtle, in: .rect(cornerRadius: 22))
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
