import SwiftUI
import KvittaCore
import KvittaStorage

/// A dedicated position view: all money remains currency-scoped and every row can open settlement.
struct PositionView: View {
    let ledger: LedgerStore
    let userId: UserID
    let profile: UserProfile
    let onProfile: () -> Void
    let onSettle: (SuggestedTransfer, GroupID) -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Ställning", subtitle: ledger.state.groups.values.contains { !$0.balances().isSettled } ? "Allt jämnt. Nästan." : "Allt är jämnt.", profile: profile, onProfile: onProfile)
                let groups = ledger.state.groupsByLastActivity
                let book = BalanceBook(groups: groups.map { BalanceBook.GroupSlice(name: $0.name, balances: $0.balances(), members: $0.members) })
                let currency = book.currencies.first ?? .sek
                if horizontalSizeClass == .regular {
                    HStack(alignment: .top, spacing: 24) {
                        BalanceHero(summary: book.summary(for: currency, userId: userId),
                                    label: "Din nettoställning · \(currency.code)",
                                    explanation: "Öppna saldon i \(groups.count) grupper")
                        BalanceFilterView(book: book, currency: currency, userId: userId, groups: groups, ledger: ledger, onSettle: onSettle)
                    }
                } else {
                    BalanceHero(summary: book.summary(for: currency, userId: userId),
                                label: "Din nettoställning · \(currency.code)",
                                explanation: "Öppna saldon i \(groups.count) grupper")
                    BalanceFilterView(book: book, currency: currency, userId: userId, groups: groups, ledger: ledger, onSettle: onSettle)
                }
                if book.currencies.count > 1 {
                    Text("Övriga valutor")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    ForEach(book.currencies.dropFirst(), id: \.self) { code in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(code.code).font(.headline.weight(.bold)).foregroundStyle(Theme.ink)
                            BalanceFilterView(book: book, currency: code, userId: userId, groups: groups, ledger: ledger, onSettle: onSettle)
                        }
                    }
                }
                settlementFooter(groups: groups, userId: userId, currency: currency)
                if ledger.state.groups.isEmpty {
                    ContentUnavailableView("Inga saldon än", systemImage: "chart.pie")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 130)
        }
        .background(AmbientBackground())
        .navigationBarHidden(true)
    }

    private func settlementFooter(groups: [GroupState], userId: UserID, currency: CurrencyCode) -> some View {
        Group {
            if let result = groups.lazy.compactMap({ group -> (SuggestedTransfer, GroupID)? in
                guard let me = group.me(for: userId) else { return nil }
                guard let transfer = group.suggestedTransfers().first(where: { $0.currency == currency && $0.from == me.id }) else { return nil }
                return (transfer, group.id)
            }).first {
                Button("Jämna ut") { onSettle(result.0, result.1) }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityHint("Öppnar reglering av första öppna saldot")
            }
        }
    }

}

private enum BalanceFilter: String, CaseIterable { case all = "Alla", receive = "Du ska få", pay = "Du ska betala" }

private struct BalanceFilterView: View {
    let book: BalanceBook
    let currency: CurrencyCode
    let userId: UserID
    let groups: [GroupState]
    let ledger: LedgerStore
    let onSettle: (SuggestedTransfer, GroupID) -> Void
    @State private var filter: BalanceFilter = .all
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var people: [BalanceBook.Person] {
        book.people(for: currency, userId: userId).filter {
            switch filter {
            case .all: true
            case .receive: $0.amountMinor > 0
            case .pay: $0.amountMinor < 0
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 4) {
                ForEach(BalanceFilter.allCases, id: \.self) { option in
                    Button(option.rawValue) { filter = option }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(filter == option ? Theme.heroText : Theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .padding(.vertical, 10)
                        .background(filter == option ? Theme.hero : Theme.card, in: .capsule)
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(filter == option ? .isSelected : [])
                }
            }
            .padding(4)
            .background(Theme.card, in: .capsule)
            .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: filter)
            Text("Mellan dig och vänner  ·  \(people.count)")
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.ink)
            if people.isEmpty {
                Text(filter == .all ? "Inga öppna saldon." : "Inga personer i det här filtret.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(people) { person in
                    PersonBalanceRow(person: person, groups: groups, ledger: ledger, userId: userId, currency: currency)
                }
            }
        }
    }

}

struct PersonBalanceRow: View {
    let person: BalanceBook.Person
    let groups: [GroupState]
    let ledger: LedgerStore
    let userId: UserID
    let currency: CurrencyCode

    private var hasRelationship: Bool {
        groups.contains { group in
            person.memberIds.contains { group.members[$0] != nil } && group.me(for: userId) != nil
        }
    }

    var body: some View {
        NavigationLink {
            if hasRelationship {
                RelationshipDetailView(ledger: ledger, userId: userId, person: person, currency: currency)
            } else {
                EmptyView()
            }
        } label: {
            HStack(spacing: 12) {
                Avatar(name: person.name, photo: nil, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(person.name).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(person.amountMinor > 0 ? "ska betala dig · \(person.context)" : person.amountMinor < 0 ? "du ska betala · \(person.context)" : "öppet åt båda håll · \(person.context)")
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(person.amountMinor == 0 ? "0 kr netto" : MoneyFormat.string(abs(person.amountMinor), person.currency))
                        .font(.body.weight(.bold)).monospacedDigit().foregroundStyle(Theme.tint(forSign: person.amountMinor))
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.tertiary)
                }
            }
            .padding(.vertical, 10)
            .frame(minHeight: 64)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(person.amountMinor > 0 ? "\(person.name) ska betala dig" : person.amountMinor < 0 ? "Du ska betala \(person.name)" : "Öppna saldon åt båda håll med \(person.name)")
    }
}

private struct RelationshipDetailView: View {
    let ledger: LedgerStore
    let userId: UserID
    let person: BalanceBook.Person
    let currency: CurrencyCode

    private var groups: [GroupState] {
        ledger.state.groupsByLastActivity.filter { group in
            guard let me = group.me(for: userId) else { return false }
            return group.members.keys.contains(where: person.memberIds.contains)
                && group.balances().suggestedTransfers.contains { transfer in
                    transfer.currency == currency
                        && ((transfer.from == me.id && person.memberIds.contains(transfer.to))
                            || (transfer.to == me.id && person.memberIds.contains(transfer.from)))
                }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(person.name)
                        .font(.system(size: 32, weight: .heavy))
                        .tracking(-0.8)
                    Text("Alla öppna saldon i \(currency.code)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }

                if groups.isEmpty {
                    ContentUnavailableView("Inga öppna poster", systemImage: "checkmark.circle")
                } else {
                    ForEach(groups) { group in
                        relationshipCard(group)
                    }
                }
            }
            .padding(20)
            .padding(.bottom, 32)
        }
        .background(AmbientBackground())
        .navigationTitle("Relation")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func relationshipCard(_ group: GroupState) -> some View {
        let me = group.me(for: userId)
        let transfers = group.balances().suggestedTransfers.filter { transfer in
            transfer.currency == currency && me.map {
                (transfer.from == $0.id && person.memberIds.contains(transfer.to))
                    || (transfer.to == $0.id && person.memberIds.contains(transfer.from))
            } ?? false
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(GroupBadge.title(of: group.name)).font(.headline.weight(.bold))
                Spacer()
                Text("\(transfers.count) poster").font(.caption).foregroundStyle(Theme.secondary)
            }
            ForEach(transfers, id: \.self) { transfer in
                HStack {
                    Text(transfer.from == me?.id ? "Du betalar" : "\(person.name) betalar")
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    Text(MoneyFormat.string(transfer.amountMinor, transfer.currency, explicit: true))
                        .font(.body.weight(.bold)).monospacedDigit()
                        .foregroundStyle(Theme.tint(forSign: transfer.from == me?.id ? -1 : 1))
                }
            }
        }
        .cardSurface(padding: 18)
    }
}
