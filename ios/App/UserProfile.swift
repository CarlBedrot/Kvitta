import SwiftUI
import KvittaCore

/// The local profile. Phone numbers sync as mutable profile data, never ledger events.
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

    /// Legacy property/key retained for installed profiles and the existing server contract.
    /// New saves use international digits for both Sweden and Denmark.
    var swishNumber: String {
        didSet { defaults.set(swishNumber, forKey: Keys.swishNumber) }
    }

    var paymentPhone: PaymentPhoneNumber? { PaymentPhoneNumber(swishNumber) }

    var swishNumberForPayment: String? { paymentPhone?.digits }

    var isPaymentProfileComplete: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && paymentPhone != nil
    }

    /// Draft fields never enter the synced profile until both are valid.
    @discardableResult
    func save(name: String, phone: String, country: PaymentPhoneNumber.Country) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let number = PaymentPhoneNumber(phone, country: country) else { return false }
        displayName = name
        swishNumber = number.digits
        return true
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

extension EnvironmentValues {
    /// Your own picture from Jag, so any screen can draw your face without it being threaded
    /// through every initialiser between here and there. Nil for everybody else — co-members'
    /// photos do not sync, so they render as their initials, and the two look deliberate side by
    /// side because the initials colour is derived from the name rather than picked.
    @Entry var myAvatarPhoto: Data?
}

/// A photo or readable initials on a neutral placeholder.
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
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.avatarBackground)
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
