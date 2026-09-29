import SwiftUI
import UIKit
import KvittaCore

/// Editorial charcoal and pastel roles from the reference. The pizza icon remains unchanged.
enum Theme {

    /// One token, both halves. Every call site stays exactly as it was — the app changes palette
    /// in one place rather than screen by screen.
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }

    // MARK: Surfaces and text

    static let bg = adaptive(light: 0xFAF9F5, dark: 0x252622)
    static let card = adaptive(light: 0xF0EFE7, dark: 0x343530)
    static let ink = adaptive(light: 0x242521, dark: 0xF5F4EC)
    static let secondary = adaptive(light: 0x65665F, dark: 0xBFC2B7)
    static let tertiary = secondary
    static let avatarBackground = adaptive(light: 0xE8E6DC, dark: 0x44463E)

    // MARK: Slice brand and actions

    /// Exact dominant background colour sampled from the shipped AppIcon.png.
    static let brandBlue = adaptive(light: 0x4FA9E8, dark: 0x4FA9E8)
    /// A darker value of the same hue for small links/icons on ivory; never a button fill.
    static let accent = adaptive(light: 0x23638D, dark: 0xC8D8CD)
    static let accentInk = Color(hex: 0x142C3D)
    static let accentPressed = brandBlue
    static let accentSubtle = adaptive(light: 0xE6F0F4, dark: 0x243149)
    static let pizzaOrange = adaptive(light: 0xA95310, dark: 0xFFB34F)
    static let pizzaRed = adaptive(light: 0xC83B25, dark: 0xFF9078)
    // Existing selection and confirmation controls share the same action pair.
    static let hero = Editorial.purple
    static let heroHighlight = accentPressed
    static let heroText = accentInk
    static let heroSecondary = accentInk

    // MARK: Money direction

    static let positive = adaptive(light: 0x327349, dark: 0x82C99B)
    static let negative = adaptive(light: 0xB83E36, dark: 0xF79891)
    static let positiveWash = adaptive(light: 0xE8F1EB, dark: 0x22352A)

    // MARK: Group identity

    /// Stable neutral shades distinguish placeholders without introducing competing accents.
    /// Names, initials and photos carry identity; group headers share the normal card surface.
    struct GroupTint: Equatable, Sendable {
        /// Behind the badge.
        let wash: Color
        /// Initials, and anything else written on the wash.
        let foreground: Color
        /// The hero card, when there is no photo to crown it.
        let hero: Color

        private init(wash: (UInt32, UInt32), foreground: (UInt32, UInt32), hero: (UInt32, UInt32)) {
            self.wash = adaptive(light: wash.0, dark: wash.1)
            self.foreground = adaptive(light: foreground.0, dark: foreground.1)
            self.hero = adaptive(light: hero.0, dark: hero.1)
        }

        static let palette: [GroupTint] = [
            0xE8E6DC, 0xEAE8DE, 0xE6E4DA, 0xE9E7DD,
            0xE7E5DB, 0xEBE9DF, 0xE5E3D9, 0xE8E6DE,
        ].map { wash in
            GroupTint(wash: (UInt32(wash), 0x30353E), foreground: (0x65665F, 0xAFB6C1), hero: (0xFAF9F5, 0x16181C))
        }

        /// Preserve the existing eight stable identity buckets in one warm neutral family.
        nonisolated static func index(for id: GroupID) -> Int {
            let sum = withUnsafeBytes(of: id.rawValue.uuid) { bytes in
                bytes.reduce(0) { $0 &+ Int($1) }
            }
            return sum % palette.count
        }

        static func forGroup(_ id: GroupID) -> GroupTint {
            palette[index(for: id)]
        }
    }

    /// Quiet warm dividers; fields retain an explicit boundary.
    static let hairline = adaptive(light: 0xD9D8CF, dark: 0x484B50)

    // MARK: The attestation control

    /// Confirmation track and label adapt together for readable contrast.
    static let controlFill = Editorial.mint
    static let controlLabel = accentInk

    /// The colour an amount takes from its sign. Never the only carrier of meaning — every amount
    /// on screen also spells its direction in words.
    static func tint(forSign amountMinor: Int64) -> Color {
        if amountMinor > 0 { return positive }
        if amountMinor < 0 { return negative }
        return secondary
    }

    // MARK: Legacy aliases

    // Sheets not yet rebuilt this round still reference the old names. Same roles, new values,
    // so the whole app shifts palette at once instead of screen by screen.
    static let cream = bg
    static let sage = positive
    static let clay = negative
    static let clayBright = accent
    static let espresso = ink
}

/// Keep prompts readable on the app's neutral surfaces.
extension Text {
    func placeholderStyle() -> Text {
        foregroundStyle(Theme.secondary)
    }
}

struct SliceField: ViewModifier {
    var invalid = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.bg, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(invalid ? Theme.negative : Theme.hairline, lineWidth: invalid ? 1.5 : 1)
            }
    }
}

struct SliceNotice: View {
    let text: String
    var tone: Color = Theme.negative

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(.footnote.weight(.medium))
            .foregroundStyle(tone)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(tone.opacity(0.1), in: .rect(cornerRadius: 14))
            .accessibilityElement(children: .combine)
    }
}

struct AmbientBackground: View {
    var body: some View {
        Theme.bg.ignoresSafeArea()
    }
}

/// Shared spacing on the continuous canvas. Forms and notices own their visible boundaries.
private struct CardSurface: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: .rect(cornerRadius: 26))
    }
}

/// The same container as `CardSurface`, but the content owns its own padding — for cards
/// where an image must bleed all the way to the rounded edge.
private struct FlushCardSurface: ViewModifier {
    var fill: Color

    func body(content: Content) -> some View {
        content
            .background(fill)
            .clipShape(.rect(cornerRadius: 26))
    }
}

/// The one thing in the dark app that gives off light.
///
/// Being square with everyone is the state Slice is always working toward, so at night that state
/// is literally the only thing lit: the settled card glows, and everything else stays quiet. This
/// is the whole budget for boldness in the dark half — spend it here and nowhere else.
///
/// Nothing in daylight: the light theme's soft green wash already reads as celebration against
/// white, and a glow on a bright ground is just a smudge.
private struct SettledGlow: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if scheme == .dark {
            content
                .shadow(color: Color(hex: 0x6CBF82).opacity(0.28), radius: 24)
                .shadow(color: Color(hex: 0x6CBF82).opacity(0.14), radius: 48)
        } else {
            content
        }
    }
}

extension View {
    func sliceField(invalid: Bool = false) -> some View {
        modifier(SliceField(invalid: invalid))
    }

    /// Default inner padding 20 (the brief's "inside cards 20–24").
    func cardSurface(padding: CGFloat = 20) -> some View {
        modifier(CardSurface(padding: padding))
    }

    /// For the "Alla är kvitt" card only. See `SettledGlow`.
    func settledGlow() -> some View {
        modifier(SettledGlow())
    }

    /// A card with edge-to-edge content — the group-photo banners. Pad inside yourself.
    func flushCardSurface(fill: Color = Theme.card) -> some View {
        modifier(FlushCardSurface(fill: fill))
    }
}

/// The primary action: logo-blue fill, dark readable text, radius 22, gentle press scale. With a quiet
/// fill and ink label it is the secondary twin beside a primary — same shape, less voice.
struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = Editorial.mint
    var label: Color = Theme.accentInk
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? label : Theme.secondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(isEnabled ? fill : Theme.avatarBackground, in: .rect(cornerRadius: 22))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// A card or row that should acknowledge the tap without shouting: slight scale, nothing else.
struct ScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(reduceMotion ? nil : .spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// An SF Symbol in a tinted rounded square — the Apple Settings row glyph, reused for quick
/// actions and list icons so the icon language is one system everywhere.
struct IconBadge: View {
    let systemImage: String
    var tint: Color = Theme.accent
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: .rect(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

extension Color {
    /// A colour from a 0xRRGGBB literal. Only used by `Theme` — views reference the named tokens.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
