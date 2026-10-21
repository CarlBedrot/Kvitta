import SwiftUI
import KvittaCore
import KvittaStorage

/// Grupper (README §1.2): a white `Steven.Card` per group, newest activity first, with
/// swipe-to-archive and a push to the archived groups behind "VISA ARKIVERADE".
struct HomeView: View {
    let ledger: LedgerStore
    let userId: UserID
    let invites: InviteModel
    let profile: UserProfile
    let photos: GroupPhotoSyncer
    let rates: RateStore
    let profiles: ProfileSyncer
    let archivedGroups: ArchivedGroupsStore
    var onNewGroup: () -> Void
    var onJoinGroup: () -> Void = {}

    var body: some View {
        let groups = ledger.state.groupsByLastActivity
        let visible = groups.filter { !archivedGroups.isArchived($0.id) }
        let archived = groups.filter { archivedGroups.isArchived($0.id) }

        List {
            // `ScreenHeader` carries its own horizontal padding, so this row gets none of its own.
            Steven.ScreenHeader(title: "Grupper", actionTitle: "Ny grupp", action: onNewGroup)
                .rowStyle(horizontal: 0, bottom: StevenMetric.cardGap)

            if groups.isEmpty {
                EmptyGroupsView(onCreate: onNewGroup, onJoin: onJoinGroup)
                    .rowStyle()
            } else {
                ForEach(visible) { group in
                    GroupRow(group: group, userId: userId)
                        // A plain `NavigationLink` row draws a disclosure chevron Steven's cards
                        // don't have (§1.2 lists no such glyph); the push still works because the
                        // invisible link underneath is what actually catches the tap — `Color.clear`
                        // fills the row's size and stays hit-testable, unlike an empty label.
                        .background(NavigationLink(value: group.id) { Color.clear })
                        .rowStyle(bottom: StevenMetric.cardGap)
                        .swipeActions(edge: .trailing) {
                            Button("Arkivera", systemImage: "archivebox") {
                                archivedGroups.archive(group.id)
                            }
                            .tint(StevenColor.accent)
                        }
                }
            }

            if !archived.isEmpty {
                ShowArchivedButton()
                    .background(NavigationLink(value: ArchivedGroupsRoute()) { Color.clear })
                    .rowStyle()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(StevenColor.screen.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationDestination(for: GroupID.self) { groupId in
            GroupDetailView(ledger: ledger, userId: userId, groupId: groupId,
                            invites: invites, profile: profile, photos: photos, rates: rates,
                            profiles: profiles)
                .toolbar(.visible, for: .navigationBar)
        }
        .navigationDestination(for: ArchivedGroupsRoute.self) { _ in
            ArchivedGroupsScreen(ledger: ledger, userId: userId, archivedGroups: archivedGroups)
                .navigationTitle("Arkiverade grupper")
                .toolbar(.visible, for: .navigationBar)
        }
    }
}

/// The pushed list behind "VISA ARKIVERADE" — the same cards, with "Återställ" instead of
/// "Arkivera". No reference image shows this screen (README §1.2: "[gissning: push, samma
/// kortlista]"), so it reuses `GroupRow` rather than inventing a second layout. Tapping a card
/// still resolves against `HomeView`'s own `navigationDestination(for: GroupID.self)` — it stays
/// an ancestor in the stack, and `NavigationStack` only wants that declared once.
private struct ArchivedGroupsScreen: View {
    let ledger: LedgerStore
    let userId: UserID
    let archivedGroups: ArchivedGroupsStore

    var body: some View {
        let groups = ledger.state.groupsByLastActivity.filter { archivedGroups.isArchived($0.id) }
        List {
            if groups.isEmpty {
                Text("Inga arkiverade grupper")
                    .stevenFont(.rowTitle)
                    .foregroundStyle(StevenColor.muted)
                    .padding(.top, 40)
                    .frame(maxWidth: .infinity)
                    .rowStyle()
            } else {
                ForEach(groups) { group in
                    GroupRow(group: group, userId: userId)
                        .background(NavigationLink(value: group.id) { Color.clear })
                        .rowStyle(bottom: StevenMetric.cardGap)
                        .swipeActions(edge: .trailing) {
                            Button("Återställ", systemImage: "arrow.uturn.backward") {
                                archivedGroups.restore(group.id)
                            }
                            .tint(StevenColor.accent)
                        }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(StevenColor.screen.ignoresSafeArea())
    }
}

/// A marker value for the archived-groups push — `NavigationPath` pushes any `Hashable`, so this
/// just needs to exist to be its own destination type alongside `GroupID`.
private struct ArchivedGroupsRoute: Hashable {}

/// "VISA ARKIVERADE" (01, 02): centred, grey, capitals.
private struct ShowArchivedButton: View {
    var body: some View {
        Text("Visa arkiverade")
            .stevenFont(.section)
            .fontWeight(.semibold)
            .foregroundStyle(StevenColor.section)
            .frame(maxWidth: .infinity, minHeight: StevenMetric.minimumHitTarget)
            .contentShape(.rect)
    }
}

/// One group: name, avatar stack, "N vänner" and the balance (§1.2). Shared by the live list and
/// the archived one — only the swipe action differs between the two.
private struct GroupRow: View {
    let group: GroupState
    let userId: UserID

    var body: some View {
        Steven.Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: group.name)
                    .stevenFont(.cardTitle)
                    .foregroundStyle(StevenColor.ink)
                    .lineLimit(2)
                Steven.AvatarStack(members: group.activeMembers, me: me?.id)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(friendCount) vänner")
                        .stevenFont(.rowTitle)
                        .foregroundStyle(StevenColor.muted)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Steven.BalanceLabel(state: balance, showsArchiveHint: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Visa grupp")
    }

    private var me: Member? { group.me(for: userId) }

    private var friendCount: Int {
        group.activeMembers.filter { $0.id != me?.id }.count
    }

    /// The largest *open* currency (§1.2: "visa den största öppna valutan"). Settled in every
    /// currency — including a group with no linked member, which nets to zero everywhere —
    /// reads as `.settled`.
    private var balance: Steven.Balance {
        let open = group.nets(for: userId).filter { $0.amountMinor != 0 }
        guard let largest = open.max(by: { abs($0.amountMinor) < abs($1.amountMinor) }) else {
            return .settled
        }
        return Steven.Balance(netMinor: largest.amountMinor, currency: largest.currency)
    }
}

extension View {
    /// The list-row boilerplate every Grupper row needs: no inset list chrome, Steven's own
    /// gutter instead (unless the row already carries its own, like `ScreenHeader`), and `bottom`
    /// as the gap to the next card (§2.3's 12 pt `cardGap`).
    fileprivate func rowStyle(horizontal: CGFloat = StevenMetric.gutter, bottom: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: horizontal, bottom: bottom, trailing: horizontal))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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

/// README §1.2, marked "[gissning]": a centred message with both ways into a group.
private struct EmptyGroupsView: View {
    var onCreate: () -> Void
    var onJoin: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Inga grupper än")
                .stevenFont(.cardTitle)
                .foregroundStyle(StevenColor.ink)
            VStack(spacing: 12) {
                Button("Skapa grupp", action: onCreate)
                    .buttonStyle(Steven.FilledButtonStyle())
                Button("Gå med via länk", action: onJoin)
                    .buttonStyle(Steven.OutlineButtonStyle())
            }
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }
}
