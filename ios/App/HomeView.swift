import SwiftUI
import KvittaCore
import KvittaStorage

/// Hem (Grupper): a status card that answers "how do we stand?" in words before numbers, then one
/// floating card per group. Calm, white-on-warm, no decoration that isn't information.
struct HomeView: View {
    let ledger: LedgerStore
    let userId: UserID
    let invites: InviteModel
    /// Carried through only to reach `SettleUpSheet`, which needs your own Swish number to build
    /// the link you send someone who owes you.
    let profile: UserProfile
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
            VStack(spacing: 16) {
                StatusCard(summary: summary)
                    .padding(.bottom, 12)

                ForEach(groups) { group in
                    NavigationLink(value: group.id) {
                        GroupCard(group: group, userId: userId)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }

                // Leave room so the last card clears the tab bar and the FAB.
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .navigationDestination(for: GroupID.self) { groupId in
            GroupDetailView(ledger: ledger, userId: userId, groupId: groupId,
                            invites: invites, profile: profile)
        }
    }
}

/// The net-across-groups figure, plus how many groups are settled — the words come first now.
/// v1 is single-currency per group and per user in practice (Nordic friend groups), so Totalt
/// reports the currency most groups use and sums the user's net within it.
struct HomeSummary {
    let totalMinor: Int64
    let currency: CurrencyCode
    let settledGroups: Int
    let groupCount: Int

    init(groups: [GroupState], userId: UserID) {
        var sums: [CurrencyCode: Int64] = [:]
        var counts: [CurrencyCode: Int] = [:]
        var settled = 0
        for group in groups {
            let net = group.net(for: userId)
            sums[net.currency, default: 0] += net.amountMinor
            counts[net.currency, default: 0] += 1
            if group.balances().byMember.values.allSatisfy({ $0 == 0 }) { settled += 1 }
        }
        let dominant = counts.max { $0.value < $1.value }?.key ?? .sek
        self.currency = dominant
        self.totalMinor = sums[dominant] ?? 0
        self.settledGroups = settled
        self.groupCount = groups.count
    }

    /// Everyone in every group is at zero — not just you.
    var allSettled: Bool { settledGroups == groupCount }
}

// MARK: - The status card

/// The one place the app editorialises. Settled is a small celebration on a green wash; anything
/// else is the sentence, the number large, and a bar filling toward done.
private struct StatusCard: View {
    let summary: HomeSummary

    var body: some View {
        if summary.allSettled {
            settledCard
        } else {
            openCard
        }
    }

    private var settledCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Alla är kvitt 🎉")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("Du har inga skulder och ingen ligger ute för dig.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Theme.positiveWash, in: .rect(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }

    private var openCard: some View {
        let direction = BalanceDirection(summary.totalMinor)
        return VStack(alignment: .leading, spacing: 8) {
            Text(statusSentence)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.secondary)

            // No leading sign: the sentence above carries the direction, and "Du ligger ute
            // med +191 kr" reads like a stutter. Colour still reinforces it.
            SignedAmountText(
                amountMinor: summary.totalMinor,
                currency: summary.currency,
                size: 40,
                sign: .none,
                accessibilityPhrase: "\(direction.spokenWord) \(MoneyFormat.string(abs(summary.totalMinor), summary.currency))"
            )
            .contentTransition(.numericText())

            SettleProgressBar(
                fraction: summary.groupCount == 0 ? 0 : Double(summary.settledGroups) / Double(summary.groupCount),
                tint: Theme.tint(forSign: summary.totalMinor)
            )
            .padding(.top, 8)

            Text("\(summary.settledGroups) av \(summary.groupCount) grupper är kvitt")
                .font(.caption)
                .foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 24)
    }

    /// Direction in words, always — the number's colour is reinforcement, never the message.
    private var statusSentence: LocalizedStringKey {
        switch BalanceDirection(summary.totalMinor) {
        case .owed: return "Du ligger ute med"
        case .owe: return "Du är skyldig"
        case .settled: return "Grupperna är inte kvitt än"
        }
    }
}

// MARK: - Group cards

private struct GroupCard: View {
    let group: GroupState
    let userId: UserID

    var body: some View {
        let net = group.net(for: userId)
        let direction = BalanceDirection(net.amountMinor)
        HStack(spacing: 14) {
            GroupBadge(name: group.name, size: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(GroupBadge.title(of: group.name))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                if direction == .settled {
                    Text("Kvitt")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.tertiary)
                } else {
                    SignedAmountText(
                        amountMinor: net.amountMinor,
                        currency: net.currency,
                        size: 17,
                        accessibilityPhrase: "\(GroupBadge.title(of: group.name)): \(direction.spokenWord) \(MoneyFormat.string(abs(net.amountMinor), net.currency))"
                    )
                    Text(direction.word)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.tertiary)
        }
        .padding(.vertical, 2)
        .cardSurface(padding: 18)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let count = String(localized: "\(group.activeMembers.count) personer")
        guard let last = group.lastActivity else { return count }
        return "\(count) · \(last.date.formatted(.relative(presentation: .named)))"
    }
}

/// The group's face: its emoji on a soft tint if the name carries one, otherwise initials.
/// Groups have no photos — expenses live on phones, not on a CDN — so the emoji people already
/// put in their group names ("🏔️ Fjällresan") is promoted to the icon instead.
struct GroupBadge: View {
    let name: String
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let emoji = Self.emoji(of: name) {
                Text(String(emoji))
                    .font(.system(size: size * 0.5))
            } else {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(width: size, height: size)
        .background(Theme.accent.opacity(0.1), in: .circle)
        .accessibilityHidden(true)
    }

    private var initials: String {
        let words = Self.title(of: name).split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    /// The first emoji anywhere in the name, so both "🏔️ Fjällresan" and "Båstad 🎾" work.
    static func emoji(of name: String) -> Character? {
        name.first { $0.unicodeScalars.contains { $0.properties.isEmojiPresentation } }
    }

    /// The name with its icon-emoji lifted out, so it is not shown twice.
    static func title(of name: String) -> String {
        guard let emoji = emoji(of: name) else { return name }
        return name
            .replacingOccurrences(of: String(emoji), with: "")
            .trimmingCharacters(in: .whitespaces)
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
                .buttonStyle(PrimaryButtonStyle())
                .fixedSize()
        }
    }
}
