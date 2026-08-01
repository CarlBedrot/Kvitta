import SwiftUI
import KvittaCore

/// Who you are on this device: a name, a picture, and the number people Swish you on.
///
/// Deliberately local. A member's name inside a group is an event in that group's log — this is
/// only the default that gets offered when you create one, plus what the Jag tab shows back to
/// you. Making it an event would mean an identity that exists outside any group, which the data
/// model does not have until users are real (M4).
///
/// The Swish number is local for a stronger reason than convention: events are immutable, so a
/// phone number written into a group log would land on every member's device forever with no way
/// to take it back (CLAUDE.md). It travels as a link you choose to send instead — see
/// `SettleUpSheet`.
@Observable
final class UserProfile {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.displayName = defaults.string(forKey: Keys.displayName) ?? ""
        self.avatarData = defaults.data(forKey: Keys.avatar)
        self.swishNumber = defaults.string(forKey: Keys.swishNumber) ?? ""
    }

    /// Empty until you set one. Falls back to "Du" wherever a name is required.
    var displayName: String {
        didSet { defaults.set(displayName, forKey: Keys.displayName) }
    }

    /// JPEG bytes, on this device only. See `ProfilePhotoNote` for why it does not sync yet.
    var avatarData: Data? {
        didSet {
            if let avatarData {
                defaults.set(avatarData, forKey: Keys.avatar)
            } else {
                defaults.removeObject(forKey: Keys.avatar)
            }
        }
    }

    /// Your own Swish number, exactly as you typed it — the field keeps your spacing so it still
    /// looks like a phone number when you come back to check it.
    var swishNumber: String {
        didSet { defaults.set(swishNumber, forKey: Keys.swishNumber) }
    }

    /// The same number in the form Swish wants, or `nil` if there is not a plausible one yet.
    /// Normalised on read rather than on write so a half-typed number is never silently rewritten
    /// underneath the cursor.
    var swishNumberForPayment: String? {
        SwishNumber.normalised(swishNumber)
    }

    var nameOrDefault: String {
        displayName.trimmingCharacters(in: .whitespaces).isEmpty ? "Du" : displayName
    }

    private enum Keys {
        static let displayName = "se.kvitta.profile.displayName"
        static let avatar = "se.kvitta.profile.avatar"
        static let swishNumber = "se.kvitta.profile.swishNumber"
    }
}

/// A round avatar: the photo if there is one, otherwise initials on a colour derived from the
/// name, so everyone in a group is reliably a different colour without anyone choosing one.
struct Avatar: View {
    let name: String
    var photo: Data?
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Avatar.colour(for: name))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first }.map(String.init)
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }

    /// Warm hues only, so an avatar never fights the cream-and-clay palette.
    static func colour(for name: String) -> Color {
        let palette: [Color] = [
            Theme.clay,
            Theme.sage,
            Color(hex: 0x9A6A4B),
            Color(hex: 0x6E7F5C),
            Color(hex: 0xB08238),
            Color(hex: 0x7C6A86)
        ]
        // Hashed by content rather than by `hashValue`, which is seeded per launch and would
        // give the same person a different colour every time the app starts.
        let seed = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
        return palette[seed % palette.count]
    }
}

extension UserDefaults {
    /// A throwaway suite so Previews never read or write the real profile.
    /// Computed rather than stored: `UserDefaults` is not `Sendable`, so a static `let` is not
    /// safe to share under Swift 6 concurrency.
    static var previewProfile: UserDefaults {
        UserDefaults(suiteName: "se.kvitta.preview") ?? .standard
    }
}

extension UIImage {
    /// Scaled down keeping its shape, so the whole picture survives — the group photo is shown
    /// entire in `GroupPhotoViewer`, and a crop here would be a crop nobody chose.
    func downscaled(maxSide: CGFloat) -> UIImage? {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }

        let scaleFactor = maxSide / longest
        let target = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        // Scale 1, not the screen's: the default renders at 3× on modern phones, which turns
        // "1200 px" into 3600 px and a ~2 MB JPEG the server's size cap rightly refuses.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Centre-cropped to a square and scaled down, so avatars are cheap to store and to draw.
    func squareThumbnail(side: CGFloat) -> UIImage? {
        let shortest = min(size.width, size.height)
        let crop = CGRect(
            x: (size.width - shortest) / 2,
            y: (size.height - shortest) / 2,
            width: shortest,
            height: shortest
        )
        guard let cropped = cgImage?.cropping(to: crop) else { return nil }

        let target = CGSize(width: side, height: side)
        // Same scale-1 story as `downscaled`: the avatar is stored at the size asked for, not
        // three times it.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
                .draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
