import SwiftUI
import UIKit

// The Steven design system (docs/reference/steven/README.md §2). Every Steven screen reads its
// colours, type and measurements from here and nowhere else — no hex literal or corner radius
// belongs in a screen. `Theme` and `Editorial` live on beside it until the last Steven issue
// removes them; nothing here references either.
//
// Components live in the `Steven` namespace (`Steven.FAB`, `Steven.Card`, …) because three of
// the names the README uses — FAB, SectionHeader, Keypad — are still taken by the screens being
// replaced. The namespace keeps both sets compiling side by side without renaming old code.

/// Namespace for the Steven components. See the files beside this one.
enum Steven {}

// MARK: - Colour

/// README §2.1 (light, sampled from the screenshots) and §6.3 (dark, derived per role).
enum StevenColor {

    /// One token, both halves, resolved from the trait collection like `Theme.adaptive`, so the
    /// in-app Ljust/Mörkt/System override (#143) reaches every token without a view knowing.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    // Surfaces
    static let screen = adaptive(light: 0xFAFAFB, dark: 0x121214)
    static let content = adaptive(light: 0xF9F9FA, dark: 0x17171A)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x1F1F23)
    static let hairline = adaptive(light: 0xDBDBDD, dark: 0x2E2E33)
    /// The lighter separator between list rows (05, 11).
    static let rowSeparator = adaptive(light: 0xEDEDEF, dark: 0x2A2A2F)
    static let pressed = adaptive(light: 0xF4F4F5, dark: 0x2A2A2F)
    /// The grey under the keypad, where a system keyboard would continue (12).
    static let keyboardBase = adaptive(light: 0xD6D9DE, dark: 0x0C0C0E)

    // Text
    static let ink = adaptive(light: 0x3A3C4A, dark: 0xF2F2F5)
    static let inkSoft = adaptive(light: 0x4B4D5B, dark: 0xD9DAE0)
    static let muted = adaptive(light: 0x9FA1AC, dark: 0x8E909B)
    static let label = adaptive(light: 0xACADB2, dark: 0x868892)
    static let section = adaptive(light: 0x7D7E85, dark: 0x9A9BA3)
    static let faint = adaptive(light: 0xC8C9CE, dark: 0x5E606A)
    static let tabInactive = adaptive(light: 0xA2A2A2, dark: 0x7A7A80)
    static let placeholder = adaptive(light: 0xC5C5C7, dark: 0x4A4B52)

    // Accent: Steven's teal is our blue (§4.1). `accent` is for text and outlines and is the
    // one that must pass 4.5:1; the fills are the icon's blue and carry no text of their own
    // except the white label on a filled button, which Steven draws the same way.
    static let accent = adaptive(light: 0x1A75B8, dark: 0x6BB8EE)
    static let accentFill = adaptive(light: 0x4FA9E8, dark: 0x4FA9E8)
    static let accentBright = adaptive(light: 0x4FA9E8, dark: 0x4FA9E8)
    static let accentDisabled = adaptive(light: 0xA9D3F3, dark: 0x2B4A62)
    static let accentTint = adaptive(light: 0xDCEEFB, dark: 0x1E3446)
    /// Glyphs drawn on `accentFill` (the FAB's plus): Steven's dark navy, in both modes.
    static let onAccentFill = adaptive(light: 0x3A3C4A, dark: 0x121214)

    // Direction
    static let owe = adaptive(light: 0xFECCB5, dark: 0xFECCB5)
    static let oweTint = adaptive(light: 0xFFF5F0, dark: 0x3A2A23)
    static let unread = adaptive(light: 0xFEEFE8, dark: 0x33241E)
    static let badge = adaptive(light: 0xFF383C, dark: 0xFF383C)
    static let chip = adaptive(light: 0xEBEBEC, dark: 0x2E2E33)

    /// Initials plates, picked stably per member. Dark mode is the same pastel at 25 % on
    /// `surface` (§6.3), pre-mixed so the plate stays opaque where avatars overlap.
    static let avatarPastels: [Color] = avatarPastelHexes.map { hex in
        adaptive(light: hex, dark: mix(hex, over: 0x1F1F23, alpha: 0.25))
    }

    static let avatarPastelHexes: [UInt32] = [
        0xD4FAF6, 0xE9E5D3, 0xFFEBE1, 0xFDE3EF, 0xE2E9F3, 0xE4F6FE, 0xFFF6D9,
    ]

    /// `top` composited at `alpha` over an opaque `bottom`, per channel, in integers.
    static func mix(_ top: UInt32, over bottom: UInt32, alpha: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let t = Double((top >> shift) & 0xFF), b = Double((bottom >> shift) & 0xFF)
            return UInt32((t * alpha + b * (1 - alpha)).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Typography

/// README §2.2. Sizes are Steven's at the default (Large) text size and scale with Dynamic Type
/// relative to the listed text style, so a 26 pt group title grows like `.title` does.
enum StevenFont: CaseIterable {
    case screenTitle, groupTitle, cardTitle, amountHero, navTitle
    case rowTitle, rowTitleBold, footnote, footnoteBold, tab, section, keypad
    /// The secondary title in the group footer amount and similar 22 pt bold figures.
    case amountLarge
    /// Tab bar labels (01, 05).
    case tabBar
    /// The payer sentence under the expense-detail avatar (15): "Carl betalade 368 kr". Its own
    /// size — nothing else in §2.2's table is 20 pt — because the bold amount run inside it needs
    /// a concrete `Text` (for `Text` concatenation), which `stevenFont` can't give: see
    /// `ExpenseDetailSheet.PayerSentence`.
    case sentence

    var size: CGFloat {
        switch self {
        case .screenTitle: 28
        case .groupTitle: 26
        case .cardTitle, .amountLarge: 22
        case .amountHero: 64
        case .navTitle, .rowTitle, .rowTitleBold: 17
        case .footnote, .footnoteBold, .tab, .section: 15
        case .keypad: 28
        case .tabBar: 13
        case .sentence: 20
        }
    }

    var weight: Font.Weight {
        switch self {
        case .screenTitle: .semibold
        case .groupTitle, .cardTitle, .amountLarge, .navTitle, .rowTitleBold, .footnoteBold, .tab: .bold
        case .amountHero: .heavy
        case .tabBar: .semibold
        case .rowTitle, .footnote, .section, .keypad, .sentence: .regular
        }
    }

    var textStyle: Font.TextStyle {
        switch self {
        case .screenTitle, .groupTitle, .keypad: .title
        case .cardTitle, .amountLarge: .title2
        case .amountHero: .largeTitle
        case .navTitle, .rowTitleBold: .headline
        case .rowTitle: .body
        case .footnote, .footnoteBold, .tab, .section: .subheadline
        case .tabBar: .caption
        case .sentence: .title3
        }
    }

    var isUppercase: Bool {
        switch self {
        case .navTitle, .tab, .section: true
        default: false
        }
    }

    var kerning: CGFloat { self == .navTitle ? 0.5 : 0 }

    /// Amounts and the keypad line their digits up.
    var isMonospacedDigit: Bool {
        switch self {
        case .amountHero, .amountLarge, .keypad: true
        default: false
        }
    }
}

private struct StevenFontModifier: ViewModifier {
    let token: StevenFont
    @ScaledMetric private var size: CGFloat

    init(token: StevenFont) {
        self.token = token
        _size = ScaledMetric(wrappedValue: token.size, relativeTo: token.textStyle)
    }

    func body(content: Content) -> some View {
        let font = Font.system(size: size, weight: token.weight)
        content
            .font(token.isMonospacedDigit ? font.monospacedDigit() : font)
            .kerning(token.kerning)
            .textCase(token.isUppercase ? .uppercase : nil)
    }
}

extension View {
    /// The Steven type token: size, weight, Dynamic Type scaling, case and kerning in one.
    func stevenFont(_ token: StevenFont) -> some View {
        modifier(StevenFontModifier(token: token))
    }
}

// MARK: - Metrics

/// README §2.3, in points.
enum StevenMetric {
    static let gutter: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let cardGap: CGFloat = 12
    static let cardRadius: CGFloat = 8
    static let controlRadius: CGFloat = 6
    static let rowHeight: CGFloat = 60
    static let formRowHeight: CGFloat = 55
    static let buttonHeight: CGFloat = 50
    static let compactButtonHeight: CGFloat = 44
    static let outlineWidth: CGFloat = 1.5
    static let fab: CGFloat = 60
    static let avatarStack: CGFloat = 38
    static let avatarStackOverlap: CGFloat = 4
    static let avatarRow: CGFloat = 40
    static let avatarHeader: CGFloat = 44
    static let avatarHero: CGFloat = 70
    static let iconCircle: CGFloat = 44
    static let listIcon: CGFloat = 24
    static let tabUnderline: CGFloat = 3
    static let tabRowHeight: CGFloat = 48
    static let navBarHeight: CGFloat = 56
    static let keypadRowHeight: CGFloat = 53
    static let checkBox: CGFloat = 24
    /// The smallest tap target anything gets (#139).
    static let minimumHitTarget: CGFloat = 44
}

// MARK: - Shadows

/// README §2.3: "Kortskugga: svart 10 %, radie 3, y 1. FAB: svart 15 %, radie 8, y 3.
/// Footer: svart 6 %, radie 6, y −2."
enum StevenShadow {
    case card, fab, footer, chip

    var opacity: Double {
        switch self {
        case .card: 0.10
        case .fab: 0.15
        case .footer: 0.06
        case .chip: 0.12
        }
    }

    var radius: CGFloat {
        switch self {
        case .card, .chip: 3
        case .fab: 8
        case .footer: 6
        }
    }

    var y: CGFloat {
        switch self {
        case .card, .chip: 1
        case .fab: 3
        case .footer: -2
        }
    }
}

extension View {
    func stevenShadow(_ shadow: StevenShadow) -> some View {
        self.shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
    }
}
