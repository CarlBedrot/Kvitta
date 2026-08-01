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
    let photos: GroupPhotoSyncer
    let rates: RateStore
    let profiles: ProfileSyncer
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
                StatusCard(summary: summary, rates: rates.rates)
                    .padding(.bottom, 12)

                ForEach(groups) { group in
                    NavigationLink(value: group.id) {
                        GroupCard(group: group, userId: userId,
                                  photo: photos.images.image(for: group.id))
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
                            invites: invites, profile: profile, photos: photos, rates: rates,
                            profiles: profiles)
        }
    }
}

/// The net-across-groups figure, plus how many groups are settled — the words come first now.
/// v1 is single-currency per group and per user in practice (Nordic friend groups), so Totalt
/// reports the currency most groups use and sums the user's net within it.
struct HomeSummary {
    /// Your net per currency across all groups, largest bucket count first. Since M7 every
    /// bucket is shown — the old version silently dropped everything but the dominant currency,
    /// which was a lie of omission the moment a second currency held real money.
    let totals: [Money]
    let settledGroups: Int
    let groupCount: Int

    init(groups: [GroupState], userId: UserID) {
        var sums: [CurrencyCode: Int64] = [:]
        var primaries: [CurrencyCode: Int] = [:]
        var settled = 0
        for group in groups {
            for net in group.nets(for: userId) {
                sums[net.currency, default: 0] += net.amountMinor
            }
            primaries[group.currency, default: 0] += 1
            if group.balances().isSettled { settled += 1 }
        }
        // The currency most groups call home leads — a DKK side-bucket must not out-rank the
        // SEK your groups actually live in. Ties break on code so two devices agree.
        self.totals = sums
            .map { Money(amountMinor: $0.value, currency: $0.key) }
            .sorted { lhs, rhs in
                let l = primaries[lhs.currency] ?? 0
                let r = primaries[rhs.currency] ?? 0
                return l == r ? lhs.currency.code < rhs.currency.code : l > r
            }
        self.settledGroups = settled
        self.groupCount = groups.count
    }

    var lead: Money { totals.first ?? .zero(.sek) }

    /// Everyone in every group is at zero — not just you.
    var allSettled: Bool { settledGroups == groupCount }
}

// MARK: - The status card

/// The one place the app editorialises. Settled is a small celebration on a green wash; anything
/// else is the sentence, the number large, and a bar filling toward done.
private struct StatusCard: View {
    let summary: HomeSummary
    let rates: ExchangeRates?

    var body: some View {
        if summary.allSettled {
            settledCard
        } else {
            openCard
        }
    }

    private var settledCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Alla är kvitt 🎉")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Du har inga skulder och ingen ligger ute för dig.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
            // The mockup puts an illustration here. No asset pipeline for one — the emoji
            // carries the same celebration at zero bytes.
            Text("🙌")
                .font(.system(size: 44))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Theme.positiveWash, in: .rect(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }

    private var openCard: some View {
        let lead = summary.lead
        let direction = BalanceDirection(lead.amountMinor)
        return VStack(alignment: .leading, spacing: 8) {
            Text(statusSentence)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.secondary)

            // No leading sign: the sentence above carries the direction, and "Du ligger ute
            // med +191 kr" reads like a stutter. Colour still reinforces it.
            SignedAmountText(
                amountMinor: lead.amountMinor,
                currency: lead.currency,
                size: 40,
                sign: .none,
                // Explicit the moment currencies mix: "200 kr" that means 200 DKK is the exact
                // lie the kr-collision rule exists to prevent.
                explicit: summary.totals.count > 1,
                accessibilityPhrase: "\(direction.spokenWord) \(MoneyFormat.string(abs(lead.amountMinor), lead.currency, explicit: true))"
            )
            .contentTransition(.numericText())

            // The other currencies, exact, with explicit codes — "kr" alone cannot say which
            // kronor once SEK and DKK share a screen. Each line carries its own direction
            // word: the sentence above only speaks for the lead line, and a second bucket can
            // point the other way (how-kvitta-works.md §10.1).
            ForEach(summary.totals.dropFirst(), id: \.currency) { total in
                HStack(spacing: 6) {
                    Text(BalanceDirection(total.amountMinor).word)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                    SignedAmountText(
                        amountMinor: total.amountMinor,
                        currency: total.currency,
                        size: 22,
                        explicit: true
                    )
                }
            }

            SettleProgressBar(
                fraction: summary.groupCount == 0 ? 0 : Double(summary.settledGroups) / Double(summary.groupCount),
                tint: Theme.tint(forSign: lead.amountMinor)
            )
            .padding(.top, 8)

            HStack(spacing: 6) {
                Text("\(summary.settledGroups) av \(summary.groupCount) grupper är kvitt")
                if let approx = approximateTotal {
                    Text(verbatim: "·")
                    Text("≈ \(MoneyFormat.string(approx.amountMinor, approx.currency, sign: .always, explicit: true)) totalt")
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 24)
    }

    /// Everything folded into the lead currency at ECB rates — a caption, never the headline.
    /// `nil` with one bucket (nothing to add), without rates, or if any bucket cannot convert.
    private var approximateTotal: Money? {
        guard summary.totals.count > 1, let rates else { return nil }
        let target = summary.lead.currency
        var totalMinor: Int64 = 0
        for total in summary.totals {
            guard let converted = rates.convert(total, to: target) else { return nil }
            totalMinor += converted.amountMinor
        }
        return Money(amountMinor: totalMinor, currency: target)
    }

    /// Direction in words, always — the number's colour is reinforcement, never the message.
    private var statusSentence: LocalizedStringKey {
        switch BalanceDirection(summary.lead.amountMinor) {
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
    let photo: Data?

    var body: some View {
        // The group's photo spans the card as a banner; the small circle then falls back to the
        // emoji so the same picture is not shown twice on one card.
        VStack(spacing: 0) {
            if let photo {
                GroupPhotoBanner(photo: photo)
            }
            row
                .padding(18)
        }
        .flushCardSurface()
        .accessibilityElement(children: .combine)
    }

    private var row: some View {
        let nets = group.nets(for: userId).filter { $0.amountMinor != 0 }
        let net = nets.first ?? group.net(for: userId)
        let direction: BalanceDirection = nets.isEmpty ? .settled : BalanceDirection(net.amountMinor)
        return HStack(spacing: 14) {
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
                        explicit: net.currency != group.currency,
                        accessibilityPhrase: "\(GroupBadge.title(of: group.name)): \(direction.spokenWord) \(MoneyFormat.string(abs(net.amountMinor), net.currency, explicit: true))"
                    )
                    // Money never wraps mid-amount; the group name is what gives way.
                    .lineLimit(1)
                    .fixedSize()
                    Text(direction.word)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondary)
                    // A second currency in play: one small exact line, not a hidden truth —
                    // and each line carries its *own* direction word, because "+191,33 kr /
                    // −200 DKK" under a single "du ska få" genuinely got misread as a
                    // conversion (how-kvitta-works.md §10.1). Buckets can point opposite ways.
                    ForEach(nets.dropFirst(), id: \.currency) { extra in
                        HStack(spacing: 4) {
                            Text(BalanceDirection(extra.amountMinor).word)
                                .font(.caption2)
                                .foregroundStyle(Theme.secondary)
                            SignedAmountText(
                                amountMinor: extra.amountMinor,
                                currency: extra.currency,
                                size: 12,
                                explicit: true
                            )
                        }
                        .lineLimit(1)
                        .fixedSize()
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.tertiary)
        }
    }

    private var subtitle: String {
        let count = String(localized: "\(group.activeMembers.count) personer")
        guard let last = group.lastActivity else { return count }
        return "\(count) · \(last.date.formatted(.relative(presentation: .named)))"
    }
}

/// The group's photo across the full width of a card — how a picked picture actually gets seen,
/// on the Grupper list and atop the group screen's hero. Pair with `flushCardSurface` so the
/// image bleeds to the rounded edge.
struct GroupPhotoBanner: View {
    let photo: Data
    var height: CGFloat = 84

    var body: some View {
        if let image = UIImage(data: photo) {
            // Clear frame + overlay, so scaledToFill cannot push the card wider than the screen.
            Color.clear
                .frame(height: height)
                .overlay { Image(uiImage: image).resizable().scaledToFill() }
                .clipped()
                .accessibilityHidden(true)
        }
    }
}

/// The group's face: your photo for it if you have set one — with the name's emoji as a corner
/// badge, the mockup's treatment — otherwise the emoji on a soft tint, otherwise initials.
///
/// The photo is this device's own (`GroupImageStore`): a photo in the immutable log would reach
/// every member forever, so instead everyone decorates their own list, like contacts.
struct GroupBadge: View {
    let name: String
    var photo: Data? = nil
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(.circle)
                    .overlay(alignment: .bottomTrailing) {
                        if let emoji = Self.emoji(of: name) {
                            Text(String(emoji))
                                .font(.system(size: size * 0.32))
                                .padding(1)
                                .background(Theme.card, in: .circle)
                                .offset(x: 2, y: 2)
                        }
                    }
            } else if let emoji = Self.emoji(of: name) {
                Text(String(emoji))
                    .font(.system(size: size * 0.5))
                    .frame(width: size, height: size)
                    .background(Theme.accent.opacity(0.1), in: .circle)
            } else {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: size, height: size)
                    .background(Theme.accent.opacity(0.1), in: .circle)
            }
        }
        .accessibilityHidden(true)
    }

    private var initials: String {
        let words = Self.title(of: name).split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    /// The first emoji anywhere in the name, so both "🏔️ Fjällresan" and "Båstad 🎾" work.
    /// `nonisolated`: pure string work, also called from ShareLink's export closure, which runs
    /// off the main actor — an implicit @MainActor here is a runtime trap, not a type error.
    nonisolated static func emoji(of name: String) -> Character? {
        name.first { character in
            guard let first = character.unicodeScalars.first, first.properties.isEmoji else {
                return false
            }
            // Pictographs like 🏖️ have Emoji_Presentation false and rely on a variation
            // selector, so a multi-scalar emoji character counts too. Plain digits are isEmoji
            // but single-scalar and text-presenting, so they stay excluded.
            return first.properties.isEmojiPresentation || character.unicodeScalars.count > 1
        }
    }

    /// The name with its icon-emoji lifted out, so it is not shown twice.
    nonisolated static func title(of name: String) -> String {
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
