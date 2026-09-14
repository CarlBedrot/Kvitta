import SwiftUI
import KvittaCore
import KvittaStorage

/// Grupper: the list, and nothing above it. One row per group — name, and where you stand in
/// it — because "how do we stand?" is answered by the rows themselves, not by a card summing
/// them up. Calm, warm, no decoration that isn't information.
struct HomeView: View {
    let ledger: LedgerStore
    let userId: UserID
    let invites: InviteModel
    let profile: UserProfile
    let photos: GroupPhotoSyncer
    let rates: RateStore
    let profiles: ProfileSyncer
    var onNewGroup: () -> Void
    var onJoin: () -> Void

    var body: some View {
        // Sorted once per render: the sort scans every ledger event.
        let groups = ledger.state.groupsByLastActivity
        Group {
            if groups.isEmpty {
                EmptyGroupsView(onNewGroup: onNewGroup)
            } else {
                content(groups: groups)
            }
        }
        .background(AmbientBackground())
        .navigationTitle("Grupper")
        // Creating and joining live up here, by the title, where iOS users look for "new" —
        // not under the floating button, which is for the thing you do ten times as often.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: onNewGroup) {
                        Label("Ny grupp", systemImage: "person.badge.plus")
                    }
                    Button(action: onJoin) {
                        Label("Gå med via länk", systemImage: "envelope")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .accessibilityLabel("Ny grupp eller gå med")
                }
            }
        }
    }

    private func content(groups: [GroupState]) -> some View {
        ScrollView {
            // Plain rows with a hairline between them, the way a list of things you can open
            // looks in every native app — not a card per group. Lazy: a row is built when it
            // scrolls into view.
            LazyVStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 {
                        Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 62)
                    }
                    NavigationLink(value: group.id) {
                        GroupRow(group: group, nets: group.nets(for: userId))
                    }
                    .buttonStyle(ScaleButtonStyle())
                }

                // Leave room so the last row clears the tab bar and the FAB.
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

// MARK: - Group rows

/// Badge, name, and your position — signed and coloured, no direction word: "+191,33 kr" in
/// green is the sentence. Two currencies stack on the right; nothing else is on the row.
private struct GroupRow: View {
    let group: GroupState
    /// Your position in this group per currency, from one fold.
    let nets: [Money]

    var body: some View {
        let open = nets.filter { $0.amountMinor != 0 }
        HStack(spacing: 14) {
            GroupBadge(name: group.name, size: 48, groupId: group.id)

            Text(GroupBadge.title(of: group.name))
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            if open.isEmpty {
                Text("Kvitt")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.tertiary)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    ForEach(open, id: \.currency) { bucket in
                        SignedAmountText(
                            amountMinor: bucket.amountMinor,
                            currency: bucket.currency,
                            size: 17,
                            explicit: bucket.currency != group.currency || open.count > 1,
                            accessibilityPhrase: "\(GroupBadge.title(of: group.name)): \(BalanceDirection(bucket.amountMinor).spokenWord) \(MoneyFormat.string(abs(bucket.amountMinor), bucket.currency, explicit: true))"
                        )
                        // Money never wraps mid-amount; the group name is what gives way.
                        .lineLimit(1)
                        .fixedSize()
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.tertiary)
        }
        .padding(.vertical, 14)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// The group's photo across the full width of a card — how a picked picture actually gets seen,
/// on the Grupper list and atop the group screen's hero. Pair with `flushCardSurface` so the
/// image bleeds to the rounded edge. Takes the already-decoded image (`GroupImageStore.uiImage`)
/// so scrolling never re-decodes a JPEG mid-frame.
struct GroupPhotoBanner: View {
    let image: UIImage
    var height: CGFloat = 84
    /// When set, the banner takes its height from the image's own shape — width divided by this
    /// ratio, clamped to the range — instead of a fixed strip. The group screen's hero uses it so
    /// a portrait picture shows most of itself rather than a 120 pt sliver; the Grupper list keeps
    /// the fixed height, because a scrolling list wants even rows more than it wants whole photos.
    var aspect: ClosedRange<CGFloat>? = nil

    var body: some View {
        // Clear frame + overlay, so scaledToFill cannot push the card wider than the screen.
        Color.clear
            .modifier(BannerShape(height: height, aspect: aspect, image: image))
            .overlay { Image(uiImage: image).resizable().scaledToFill() }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// The two sizing modes of `GroupPhotoBanner`, kept out of its body.
private struct BannerShape: ViewModifier {
    let height: CGFloat
    let aspect: ClosedRange<CGFloat>?
    let image: UIImage

    func body(content: Content) -> some View {
        if let aspect {
            let own = image.size.width / max(image.size.height, 1)
            content.aspectRatio(min(max(own, aspect.lowerBound), aspect.upperBound), contentMode: .fit)
        } else {
            content.frame(height: height)
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
    var photo: UIImage? = nil
    var size: CGFloat = 44
    /// The group's own colour — see `Theme.GroupTint`. Without an id (previews, callers that
    /// only have a name) the badge falls back to the accent wash it always had.
    var groupId: GroupID? = nil

    private var wash: Color { groupId.map { Theme.GroupTint.forGroup($0).wash } ?? Theme.accent.opacity(0.1) }
    private var letters: Color { groupId.map { Theme.GroupTint.forGroup($0).foreground } ?? Theme.accent }

    var body: some View {
        Group {
            if let image = photo {
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
                    .background(wash, in: .circle)
            } else {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(letters)
                    .frame(width: size, height: size)
                    .background(wash, in: .circle)
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
        } actions: {
            Button("Ny grupp", action: onNewGroup)
                .buttonStyle(PrimaryButtonStyle())
                .fixedSize()
        }
    }
}
