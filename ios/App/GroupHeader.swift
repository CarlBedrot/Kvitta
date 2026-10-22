import SwiftUI
import KvittaCore

/// The group screen's own top bar (08–10, §6.2): `‹` back, `•••` menu, no title — the big name
/// sits in `GroupHeader` below instead. `•••` still opens the old members/CSV menu; it becomes
/// gruppinställningar once Steven 7 (#151) builds that screen.
struct GroupNavBar: View {
    let group: GroupState
    let onBack: () -> Void
    let onMembers: () -> Void

    var body: some View {
        HStack {
            Steven.IconButton(systemName: "chevron.left", label: "Tillbaka", action: onBack)
            Spacer()
            Menu {
                Button(action: onMembers) {
                    Label("Medlemmar och inbjudan", systemImage: "person.2")
                }
                ShareLink(
                    item: CSVExportFile(group: group),
                    preview: SharePreview(CSVExportFile.filename(for: group))
                ) {
                    Label("Exportera CSV", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(StevenColor.ink)
                    .frame(width: StevenMetric.minimumHitTarget, height: StevenMetric.minimumHitTarget)
                    .contentShape(.rect)
            }
            .accessibilityLabel(Text("Mer"))
        }
        .padding(.horizontal, 6)
        .frame(minHeight: StevenMetric.navBarHeight)
        .background(StevenColor.surface)
    }
}

/// The group's head (08, decision 6.2): name and total spend, the member avatars, and — when the
/// group has a photo — that photo 180 pt tall behind all of it, dark gradient at the foot so the
/// text stays readable. No photo is "rent Steven-huvud": the same layout on a plain surface.
struct GroupHeader: View {
    let group: GroupState
    let meId: MemberID?
    /// The group's total spend, already summed by the screen's one fold (see `totalSpent`).
    let totalMinor: Int64
    let totalApproximate: Bool
    let photo: UIImage?
    let onShowPhoto: () -> Void

    private var onPhoto: Bool { photo != nil }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let photo {
                Button(action: onShowPhoto) {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .overlay(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Visa gruppbilden"))
            }
            VStack(alignment: .leading, spacing: 16) {
                titleRow
                Steven.AvatarStack(members: group.activeMembers, me: meId,
                                   size: StevenMetric.avatarHeader, overlap: -StevenMetric.gutter)
            }
            .padding(.horizontal, StevenMetric.gutter)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .background(onPhoto ? Color.clear : StevenColor.surface)
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: GroupBadge.title(of: group.name))
                .stevenFont(.groupTitle)
                .foregroundStyle(onPhoto ? .white : StevenColor.ink)
                .lineLimit(2)
            Spacer(minLength: 8)
            Text(verbatim: totalText)
                .stevenFont(.groupTitle)
                .foregroundStyle(onPhoto ? .white : StevenColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var totalText: String {
        let formatted = StevenMoneyFormat.string(totalMinor, group.currency, explicit: false)
        return totalApproximate ? "≈ \(formatted)" : formatted
    }
}
