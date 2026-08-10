import SwiftUI
import UIKit

/// The design system for the 2026 redesign: warm off-white behind pure-white floating cards,
/// one burnt-orange accent, and colour otherwise reserved for the direction of money. The aim is
/// a first-party feel — Apple Wallet, Reminders, Invites — so typography and whitespace do the
/// work borders and decoration used to.
///
/// Token names kept from the first design where the *role* survived (`ink`, `secondary`, `card`),
/// so the diff shows what actually changed: the values, and the retirement of glass.
///
/// ## The dark half
///
/// Not a second design — the same one with the lights turned down. The light palette already
/// contained its own night: `ink` was never neutral black but a *warm* near-black at hue 42°, the
/// same family as the cream. So dark mode turns the app inside out rather than inventing a new
/// scheme — the ink becomes the ground, the cream becomes the type, and every grey stays warm.
///
/// That is the whole argument against the obvious alternative. Stock dark mode is neutral
/// charcoal, and Slice's light identity is specifically a refusal of grey-blue fintech in favour
/// of something warm. A neutral dark mode would throw away the one thing that stops this looking
/// like Splitwise.
///
/// **The accent does not change between modes.** It reads 5.35:1 on the dark ground, which is
/// enough, and moving it would both shift the brand and cost contrast against the white it carries
/// on buttons. Money colours *do* change, because they had to: `positive` at its light value is
/// 3.75:1 on the dark ground and genuinely hard to read. Every dark money colour ends up with more
/// contrast than its light counterpart, not less.
enum Theme {

    /// One token, both halves. Every call site stays exactly as it was — the app changes palette
    /// in one place rather than screen by screen.
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }

    // MARK: Surfaces

    /// The screen behind everything. Warm off-white by day; by night a warm near-black a step
    /// deeper than `ink`, so cards have somewhere to sit above.
    static let bg = adaptive(light: 0xF8F5EF, dark: 0x151310)
    /// Cards are pure white and *float*. By day elevation comes from `cardSurface`'s shadow; by
    /// night a shadow on a dark ground is invisible, so the card carries its own light instead —
    /// see `CardSurface`.
    static let card = adaptive(light: 0xFFFFFF, dark: 0x221F1B)

    // MARK: Text hierarchy

    static let ink = adaptive(light: 0x1F1D1A, dark: 0xF2EEE5)
    static let secondary = adaptive(light: 0x6E6A63, dark: 0xA39C92)
    static let tertiary = adaptive(light: 0xA5A099, dark: 0x6E6860)

    // MARK: The one accent

    /// Burnt orange. The FAB, primary buttons, the selected tab — and nothing else, so the single
    /// pop of colour keeps meaning "the main thing to do here". Identical in both halves.
    static let accent = Color(hex: 0xE0643C)

    // MARK: Money direction

    /// You are owed. Green appears *only* on positive balances. The dark value is much lighter
    /// than the light one: 3.75:1 was not readable, this is 7.35:1 on a card.
    static let positive = adaptive(light: 0x3E7D4E, dark: 0x6CBF82)
    /// You owe. Distinct from the accent so a debt never looks like a button — the two sit 8° apart
    /// in hue in *both* halves, deliberately the same separation the light theme already ships,
    /// because colour is never the only carrier here: every amount also spells its direction out.
    static let negative = adaptive(light: 0xD9503F, dark: 0xE8604F)
    /// The wash behind the "Alla är kvitt 🎉" celebration card — and, at night, the one thing in
    /// the app that gives off light. See `SettledGlow`.
    static let positiveWash = adaptive(light: 0xDDEDDC, dark: 0x1B3324)

    /// Hairline separator inside cards. Used for row dividers only — never around a card.
    ///
    /// Carries its own alpha per half rather than one opacity over both: 7% ink on white is a
    /// clear line, while 7% cream on a dark card disappears. Dark surfaces need more of the
    /// lighter colour to read as the same weight of rule.
    static let hairline = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(Color(hex: 0xF2EEE5)).withAlphaComponent(0.12)
            : UIColor(Color(hex: 0x1F1D1A)).withAlphaComponent(0.07)
    })

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

/// The flat warm background. The first design layered radial washes here for glass to refract;
/// there is no glass any more, and the mockups are calmer for it.
struct AmbientBackground: View {
    var body: some View {
        Theme.bg.ignoresSafeArea()
    }
}

/// How a card says it is floating, in each half.
///
/// By day a shadow does it. By night a shadow does nothing — black on a near-black ground is
/// invisible — so the card is lighter than what it sits on and catches a hairline of light along
/// its top edge, which is what a raised surface actually does under a lamp. The stock answer is
/// luminance alone; the top edge is what keeps it reading as an object rather than a lighter
/// rectangle.
private struct Elevation: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if scheme == .dark {
            content.overlay(
                // Top-lit: bright where the light lands, gone by the bottom edge.
                LinearGradient(
                    colors: [Color(hex: 0xF2EEE5).opacity(0.10), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .mask(RoundedRectangle(cornerRadius: 28).strokeBorder(lineWidth: 1))
                .allowsHitTesting(false)
            )
            // A contact shadow still earns its place under a card lighter than its ground.
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        } else {
            // Two shadows read as one: a tight contact shadow and a wide ambient one. Both very
            // soft — harsh shadows are the fastest way to stop feeling first-party.
            content
                .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
        }
    }
}

/// The floating card: radius 28, Apple-style soft elevation. The only content container.
private struct CardSurface: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: .rect(cornerRadius: 28))
            .modifier(Elevation())
    }
}

/// The same floating card as `CardSurface`, but the content owns its own padding — for cards
/// where an image must bleed all the way to the rounded edge.
private struct FlushCardSurface: ViewModifier {
    var fill: Color

    func body(content: Content) -> some View {
        content
            .background(fill)
            .clipShape(.rect(cornerRadius: 28))
            .modifier(Elevation())
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

/// The primary action: accent fill, white text, radius 22, gentle press scale.
struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(fill, in: .rect(cornerRadius: 22))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// A card or row that should acknowledge the tap without shouting: slight scale, nothing else.
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.25), value: configuration.isPressed)
    }
}

/// The single progress bar under a balance: how much of the group (or of your groups) is settled.
/// Replaces the old two-sided zero line on summary cards — one bar filling toward done reads
/// instantly, and "done" is the state the app is always working toward.
struct SettleProgressBar: View {
    /// 0...1, already clamped by the caller's arithmetic (integer counts, never money).
    let fraction: Double
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.06))
                Capsule()
                    .fill(tint)
                    .frame(width: max(8, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
        .animation(.spring(duration: 0.35), value: fraction)
        .accessibilityHidden(true)
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
