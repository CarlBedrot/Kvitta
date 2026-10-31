import SwiftUI

/// Stored independently of identity and sync; nil lets the entire scene follow iOS live.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let defaultsKey = "se.kvitta.appearance"
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "Följ telefonen"
        case .light: "Ljust"
        case .dark: "Mörkt"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// `title` as a plain `String`, for a `Steven.ListRow`'s trailing value — which takes a
    /// `String`, not a `LocalizedStringKey`, because it is also used for numbers and amounts.
    var valueText: String {
        switch self {
        case .system: String(localized: "Följ telefonen")
        case .light: String(localized: "Ljust")
        case .dark: String(localized: "Mörkt")
        }
    }
}
