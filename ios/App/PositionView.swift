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
                PageHeader(title: "Ställning", profile: profile, onProfile: onProfile)
                let groups = ledger.state.groupsByLastActivity
                let book = BalanceBook(groups: groups.map { BalanceBook.GroupSlice(name: $0.name, balances: $0.balances(), members: $0.members) })
                let summaries = book.summariesForDisplay(userId: userId)
                let currency = summaries.first?.currency ?? .sek
                if horizontalSizeClass == .regular {
                    HStack(alignment: .top, spacing: 24) {
                        BalanceHero(summary: book.summary(for: currency, userId: userId))
                        if summaries.first?.hasOpenBalances == true {
                            BalanceFilterView(book: book, currency: currency, userId: userId, groups: groups, ledger: ledger, onSettle: onSettle)
                        }
                    }
                } else {
                    BalanceHero(summary: book.summary(for: currency, userId: userId))
                    if summaries.first?.hasOpenBalances == true {
                        BalanceFilterView(book: book, currency: currency, userId: userId, groups: groups, ledger: ledger, onSettle: onSettle)
                    }
                }
                if summaries.count > 1 {
                    Text("Övriga valutor")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    ForEach(summaries.dropFirst(), id: \.currency) { summary in
                        let code = summary.currency
                        if summary.hasOpenBalances {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(code.code).font(.headline.weight(.bold)).foregroundStyle(Theme.ink)
                                BalanceFilterView(book: book, currency: code, userId: userId, groups: groups, ledger: ledger, onSettle: onSettle)
                            }
                        } else {
                            Label("Kvitt i \(code.code)", systemImage: "checkmark")
                                .font(.subheadline).foregroundStyle(Theme.secondary)
                                .frame(minHeight: 44)
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
                Button("Betala") { onSettle(result.0, result.1) }
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
            case .receive: $0.receivableMinor > 0
            case .pay: $0.payableMinor > 0
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 4) {
                ForEach(BalanceFilter.allCases, id: \.self) { option in
                    Button(LocalizedStringKey(option.rawValue)) { filter = option }
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
                Text(filter == .all ? String(localized: "Inga öppna saldon.") : String(localized: "Inga personer i det här filtret."))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(people) { person in
                    PersonBalanceRow(person: person, groups: groups, ledger: ledger, userId: userId, currency: currency, onSettle: onSettle)
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
    let onSettle: (SuggestedTransfer, GroupID) -> Void

    private var groupContext: String { String(localized: "\(person.groupCount) grupper") }

    private var amountLabel: String {
        let amount = MoneyFormat.string(abs(person.amountMinor), person.currency, explicit: true)
        return person.receivableMinor > 0 && person.payableMinor > 0
            ? String(localized: "\(amount) netto") : amount
    }

    private var hasRelationship: Bool {
        groups.contains { group in
            person.memberIds.contains { group.members[$0] != nil } && group.me(for: userId) != nil
        }
    }

    var body: some View {
        NavigationLink {
            if hasRelationship {
                RelationshipDetailView(ledger: ledger, userId: userId, person: person, currency: currency, onSettle: onSettle)
            } else {
                EmptyView()
            }
        } label: {
            HStack(spacing: 12) {
                Avatar(name: person.name, photo: nil, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(person.name).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(person.receivableMinor > 0 && person.payableMinor > 0 ? String(localized: "öppet åt båda håll · \(groupContext)") : person.amountMinor > 0 ? String(localized: "ska betala dig · \(groupContext)") : String(localized: "du ska betala · \(groupContext)"))
                        .font(.caption).foregroundStyle(Theme.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(amountLabel)
                        .font(.body.weight(.bold)).monospacedDigit().foregroundStyle(Theme.tint(forSign: person.amountMinor))
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.tertiary)
                }
            }
            .padding(.vertical, 10)
            .frame(minHeight: 64)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Öppnar saldon per grupp")
    }
}

private struct RelationshipDetailView: View {
    let ledger: LedgerStore
    let userId: UserID
    let person: BalanceBook.Person
    let currency: CurrencyCode
    let onSettle: (SuggestedTransfer, GroupID) -> Void

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
                        .font(.title.weight(.semibold))
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
        .toolbar(.visible, for: .navigationBar)
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
                VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(transfer.from == me?.id ? String(localized: "Du betalar") : String(localized: "\(person.name) betalar"))
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    Text(MoneyFormat.string(transfer.amountMinor, transfer.currency, explicit: true))
                        .font(.body.weight(.bold)).monospacedDigit()
                        .foregroundStyle(Theme.tint(forSign: transfer.from == me?.id ? -1 : 1))
                }
                Button(transfer.from == me?.id ? "Betala" : "Gör upp") { onSettle(transfer, group.id) }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
        .cardSurface(padding: 18)
    }
}
