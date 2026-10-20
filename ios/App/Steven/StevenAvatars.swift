import SwiftUI
import UIKit
import KvittaCore

extension Steven {

    /// A member's face: their photo if we have one, otherwise initials on a pastel plate picked
    /// stably from the member id, so the same friend is the same colour on every screen and
    /// every device. Only your own photo exists today (`myAvatarPhoto`); co-members' photos do
    /// not sync, so pass `isMe` and the environment supplies yours.
    struct AvatarView: View {
        let name: String
        let id: MemberID
        var size: CGFloat = StevenMetric.avatarRow
        var isMe = false
        var photo: Data?

        @Environment(\.myAvatarPhoto) private var myPhoto

        init(member: Member, size: CGFloat = StevenMetric.avatarRow, isMe: Bool = false, photo: Data? = nil) {
            self.init(name: member.displayName, id: member.id, size: size, isMe: isMe, photo: photo)
        }

        init(name: String, id: MemberID, size: CGFloat = StevenMetric.avatarRow, isMe: Bool = false, photo: Data? = nil) {
            self.name = name
            self.id = id
            self.size = size
            self.isMe = isMe
            self.photo = photo
        }

        var body: some View {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Text(verbatim: Self.initials(of: name))
                        .font(.system(size: size * 0.45, weight: .regular))
                        .foregroundStyle(StevenColor.ink)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(StevenColor.avatarPastels[Self.pastelIndex(for: id)])
                }
            }
            .frame(width: size, height: size)
            .clipShape(.circle)
            .accessibilityHidden(true)
        }

        private var image: UIImage? {
            guard let data = photo ?? (isMe ? myPhoto : nil) else { return nil }
            return UIImage(data: data)
        }

        /// "Ellen Ekwall" → "EE", "carl" → "C". Two letters at most, as in 01.
        static func initials(of name: String) -> String {
            let letters = name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init)
            return letters.isEmpty ? "?" : letters.joined().uppercased()
        }

        /// Stable across launches and devices: derived from the id's bytes, never `hashValue`,
        /// which Swift reseeds every run.
        nonisolated static func pastelIndex(for id: MemberID) -> Int {
            let sum = withUnsafeBytes(of: id.rawValue.uuid) { bytes in
                bytes.reduce(0) { $0 &+ Int($1) }
            }
            return sum % StevenColor.avatarPastelHexes.count
        }
    }

    /// Overlapping faces, you first and then everybody else by name (01, 11). Earlier faces sit on
    /// top, the way Steven stacks them.
    struct AvatarStack: View {
        let members: [Member]
        var me: MemberID?
        var size: CGFloat = StevenMetric.avatarStack
        var overlap: CGFloat = StevenMetric.avatarStackOverlap

        var body: some View {
            HStack(spacing: -overlap) {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, member in
                    AvatarView(member: member, size: size, isMe: member.id == me)
                        .zIndex(Double(ordered.count - index))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: ordered.map(\.displayName).formatted(.list(type: .and))))
        }

        private var ordered: [Member] {
            members.sorted { lhs, rhs in
                if lhs.id == me { return rhs.id != me }
                if rhs.id == me { return false }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
        }
    }
}

#Preview("Avatars – light") { StevenAvatarPreview() }
#Preview("Avatars – dark") { StevenAvatarPreview().preferredColorScheme(.dark) }

private struct StevenAvatarPreview: View {
    var body: some View {
        VStack(spacing: 24) {
            Steven.AvatarStack(members: StevenPreviewData.members, me: StevenPreviewData.members[0].id)
            HStack(spacing: 16) {
                ForEach(StevenPreviewData.members.prefix(4)) { member in
                    Steven.AvatarView(member: member, size: StevenMetric.avatarHeader)
                }
            }
            Steven.AvatarView(member: StevenPreviewData.members[1], size: StevenMetric.avatarHero)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StevenColor.screen)
    }
}

/// Fixed sample members for previews and the DEBUG gallery. Fixed UUIDs, so the pastels in a
/// preview are the pastels in a screenshot.
enum StevenPreviewData {
    static let members: [Member] = [
        ("Carl Bedrot", "00000000-0000-0000-0000-000000000001"),
        ("Anna Lind", "00000000-0000-0000-0000-000000000002"),
        ("David Tran", "00000000-0000-0000-0000-000000000003"),
        ("Greta Holm", "00000000-0000-0000-0000-000000000004"),
        ("Hugo Gran", "00000000-0000-0000-0000-000000000005"),
        ("Jonas Falk", "00000000-0000-0000-0000-000000000006"),
        ("Olle Tegnér", "00000000-0000-0000-0000-000000000007"),
    ].map { name, uuid in
        Member(id: MemberID(rawValue: UUID(uuidString: uuid)!), displayName: name)
    }
}
