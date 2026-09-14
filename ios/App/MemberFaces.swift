import SwiftUI
import KvittaCore

/// A row of overlapping faces — the people in a group or in a split, read at a glance. Up to
/// `shown` avatars, then "+n". Only your own face can carry a photo; everyone else is initials,
/// the same contacts-style rule as everywhere (photos decorate your device, never the group).
struct MemberFaces: View {
    let members: [Member]
    let meId: MemberID?
    let myPhoto: Data?
    let name: (Member) -> String
    var size: CGFloat = 28
    var shown = 5

    var body: some View {
        let visible = members.prefix(shown)
        let overflow = members.count - visible.count
        HStack(spacing: -size * 0.28) {
            ForEach(Array(visible), id: \.id) { member in
                Avatar(name: name(member), photo: member.id == meId ? myPhoto : nil, size: size)
                    .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 2))
            }
            if overflow > 0 {
                Text(verbatim: "+\(overflow)")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: size, height: size)
                    .background(Theme.card, in: .circle)
                    .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}
