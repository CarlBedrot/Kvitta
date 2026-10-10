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
}
