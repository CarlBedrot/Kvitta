import SwiftUI
import KvittaCore
import KvittaStorage

/// Groups use the same purple canvas and layered illustrated cards as Categories.
struct HomeView: View {
    let ledger: LedgerStore
    let userId: UserID
    let invites: InviteModel
    let profile: UserProfile
    let photos: GroupPhotoSyncer
    let rates: RateStore
    let profiles: ProfileSyncer
    var onNewGroup: () -> Void
    var onProfile: () -> Void = {}
    @State private var searchText = ""

    var body: some View {
        let groups = ledger.state.groupsByLastActivity
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleGroups = query.isEmpty ? groups : groups.filter { $0.name.localizedCaseInsensitiveContains(query) }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    EditorialHeading(title: String(localized: "Grupper"), dark: true)
                    EditorialCircleButton(symbol: "person.crop.circle", label: String(localized: "Profil"), action: onProfile)
                }
                EditorialPill(title: String(localized: "Ny grupp"), action: onNewGroup)
                if groups.isEmpty {
                    EmptyGroupsView(onNewGroup: onNewGroup)
                } else {
                    searchField
                    if visibleGroups.isEmpty {
                        Text("Inga grupper matchar sökningen.")
                            .font(.subheadline).foregroundStyle(Editorial.coal)
                            .padding(.vertical, 20)
                    }
                    groupCards(visibleGroups)
                }
            }.padding(20).padding(.bottom, 100)
        }
        .background(Editorial.purple.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationDestination(for: GroupID.self) { groupId in
            GroupDetailView(ledger: ledger, userId: userId, groupId: groupId,
                            invites: invites, profile: profile, photos: photos, rates: rates,
                            profiles: profiles)
                .toolbar(.visible, for: .navigationBar)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").accessibilityHidden(true)
            TextField("Sök grupper", text: $searchText,
                      prompt: Text("Sök grupper").foregroundStyle(Editorial.coal.opacity(0.7)))
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                }.accessibilityLabel("Rensa sökning")
            }
        }.font(.subheadline).foregroundStyle(Editorial.coal).tint(Editorial.coal)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .background(Editorial.paper, in: .capsule)
    }

    private func groupCards(_ groups: [GroupState]) -> some View {
        // The most recently active group is the illustrated front card. Every visible
        // layer is a different group, with enough exposed height for a full tap target.
        let stacked = Array(groups.reversed())
        return LazyVStack(spacing: -16) {
            ForEach(Array(stacked.enumerated()), id: \.element.id) { index, group in
                NavigationLink(value: group.id) {
                    GroupCard(group: group, photo: photos.images.uiImage(for: group.id),
                              isFront: index == stacked.count - 1, dark: index % 2 == 1)
                }.buttonStyle(.plain)
            }
        }.frame(maxWidth: 520).frame(maxWidth: .infinity)
    }
}

/// A picker layer shows group identity only; counts and money belong inside the group.
struct GroupCard: View {
    let group: GroupState
    let photo: UIImage?
    let isFront: Bool
    let dark: Bool

    private var fill: Color { isFront ? Editorial.yellow : dark ? Editorial.coal : Editorial.coral }
    private var ink: Color { !isFront && dark ? Editorial.paper : Editorial.coal }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(GroupBadge.title(of: group.name).uppercased())
                    .font(Editorial.heading(isFront ? 30 : 24))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 17, weight: .medium))
                    .frame(width: 32, height: 32)
                    .background(ink.opacity(0.08), in: .circle)
            }
            if isFront {
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFit().frame(maxHeight: 190)
                        .frame(maxWidth: .infinity).clipShape(.rect(cornerRadius: 16))
                } else {
                    Image("SharedDinner").resizable().scaledToFit().frame(maxHeight: 190)
                        .frame(maxWidth: .infinity)
                }
            }
        }.foregroundStyle(ink)
            .padding(.horizontal, 18).padding(.top, 16)
            .padding(.bottom, isFront ? 16 : 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: .rect(cornerRadius: 26))
            .contentShape(.rect)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GroupBadge.title(of: group.name))
            .accessibilityHint("Visa grupp")
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
        Button(action: onNewGroup) {
            EditorialPanel(fill: Editorial.yellow) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Inga grupper än").font(Editorial.heading(30))
                    Image("SharedDinner").resizable().scaledToFit().frame(maxHeight: 190)
                        .frame(maxWidth: .infinity).accessibilityHidden(true)
                    Label("Skapa grupp", systemImage: "plus").font(.caption.weight(.semibold))
                }.foregroundStyle(Editorial.coal)
            }
        }.buttonStyle(.plain)
    }
}
