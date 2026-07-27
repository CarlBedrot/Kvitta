import SwiftUI
import KvittaCore
import KvittaStorage

/// Hem (Grupper): the Totalt card, the group rows, and the zero line. Content is opaque and calm;
/// the only glass on this screen is the tab bar and the FAB, both owned by `RootView`.
struct HomeView: View {
    let ledger: LedgerStore
    let userId: UserID
    var onNewGroup: () -> Void

    private var groups: [GroupState] { ledger.state.groupsByLastActivity }

    var body: some View {
        Group {
            if groups.isEmpty {
                EmptyGroupsView(onNewGroup: onNewGroup)
            } else {
                content
            }
        }
        .background(AmbientBackground())
        .navigationTitle("Grupper")
    }

    private var content: some View {
        let summary = HomeSummary(groups: groups, userId: userId)
        return ScrollView {
            VStack(spacing: 14) {
                TotaltCard(summary: summary)
                GroupsCard(groups: groups, userId: userId, scaleMinor: summary.rowScaleMinor)
                // Leave room so the last row clears the floating tab bar.
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
        .navigationDestination(for: GroupID.self) { groupId in
            GroupDetailView(ledger: ledger, userId: userId, groupId: groupId)
        }
    }
}

/// The net-across-groups figure. v1 is single-currency per group and per user in practice (Nordic
/// friend groups), so Totalt reports the currency most groups use and sums the user's net within
/// it. Amounts in another currency are excluded rather than added across scales.
private struct HomeSummary {
    let totalMinor: Int64
    let currency: CurrencyCode
    let rowScaleMinor: Int64

    init(groups: [GroupState], userId: UserID) {
        var sums: [CurrencyCode: Int64] = [:]
        var counts: [CurrencyCode: Int] = [:]
        var maxMagnitude: Int64 = 0
        for group in groups {
            let net = group.net(for: userId)
            sums[net.currency, default: 0] += net.amountMinor
            counts[net.currency, default: 0] += 1
            maxMagnitude = max(maxMagnitude, abs(net.amountMinor))
        }
        let dominant = counts.max { $0.value < $1.value }?.key ?? .sek
        self.currency = dominant
        self.totalMinor = sums[dominant] ?? 0
        self.rowScaleMinor = maxMagnitude
    }
}

private struct TotaltCard: View {
    let summary: HomeSummary

    var body: some View {
        let direction = BalanceDirection(summary.totalMinor)
        VStack(alignment: .leading, spacing: 0) {
            Text("Totalt").font(.subheadline).foregroundStyle(Theme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SignedAmountText(
                    amountMinor: summary.totalMinor,
                    currency: summary.currency,
                    size: 34,
                    accessibilityPhrase: "\(direction.spokenWord) \(MoneyFormat.string(abs(summary.totalMinor), summary.currency))"
                )
                Text(direction.word).font(.footnote).foregroundStyle(Theme.secondary)
            }
            .padding(.top, 2)
            ZeroLine(
                amountMinor: summary.totalMinor,
                scaleMinor: max(summary.rowScaleMinor, abs(summary.totalMinor))
            )
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

private struct GroupsCard: View {
    let groups: [GroupState]
    let userId: UserID
    let scaleMinor: Int64

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
                NavigationLink(value: group.id) {
                    GroupRow(group: group, userId: userId, scaleMinor: scaleMinor)
                }
                .buttonStyle(.plain)
            }
        }
        .cardSurface(padding: 6)
    }
}

private struct GroupRow: View {
    let group: GroupState
    let userId: UserID
    let scaleMinor: Int64

    var body: some View {
        let net = group.net(for: userId)
        let direction = BalanceDirection(net.amountMinor)
        VStack(spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.name).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    SignedAmountText(
                        amountMinor: net.amountMinor,
                        currency: net.currency,
                        size: 16,
                        accessibilityPhrase: "\(group.name): \(direction.spokenWord) \(MoneyFormat.string(abs(net.amountMinor), net.currency))"
                    )
                    Text(direction.word).font(.caption2).foregroundStyle(Theme.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(hex: 0xC6BDAE))
            }
            ZeroLine(amountMinor: net.amountMinor, scaleMinor: scaleMinor, mini: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyGroupsView: View {
    var onNewGroup: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Inga grupper än", systemImage: "person.2")
        } description: {
            Text("Skapa en grupp för att börja dela utgifter.")
        } actions: {
            Button("Ny grupp", action: onNewGroup)
                .buttonStyle(.glassProminent)
                // `.glassProminent` picks up the system accent, which is blue. Clay is the
                // app's one pop of colour and already means "the primary action here".
                .tint(Theme.clayBright)
        }
    }
}
