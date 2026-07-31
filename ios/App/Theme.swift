import SwiftUI

/// The design system for the 2026 redesign: warm off-white behind pure-white floating cards,
/// one burnt-orange accent, and colour otherwise reserved for the direction of money. The aim is
/// a first-party feel — Apple Wallet, Reminders, Invites — so typography and whitespace do the
/// work borders and decoration used to.
///
/// Token names kept from the first design where the *role* survived (`ink`, `secondary`, `card`),
/// so the diff shows what actually changed: the values, and the retirement of glass.
enum Theme {
    // MARK: Surfaces

    /// The screen behind everything. Warm off-white — calm, never sterile.
    static let bg = Color(hex: 0xF8F5EF)
    /// Cards are pure white and *float*: elevation comes from `cardSurface`'s shadow, never from
    /// an outline.
    static let card = Color.white

    // MARK: Text hierarchy

    static let ink = Color(hex: 0x1F1D1A)
    static let secondary = Color(hex: 0x6E6A63)
    static let tertiary = Color(hex: 0xA5A099)

    // MARK: The one accent

    /// Burnt orange. The FAB, primary buttons, the selected tab — and nothing else, so the single
    /// pop of colour keeps meaning "the main thing to do here".
    static let accent = Color(hex: 0xE0643C)

    // MARK: Money direction

    /// You are owed. Green appears *only* on positive balances.
    static let positive = Color(hex: 0x3E7D4E)
    /// You owe. Distinct from the accent so a debt never looks like a button.
    static let negative = Color(hex: 0xD9503F)
    /// The soft green wash behind the "Alla är kvitt 🎉" celebration card.
    static let positiveWash = Color(hex: 0xDDEDDC)

    /// Hairline separator inside cards. Used for row dividers only — never around a card.
    static let hairline = Color(hex: 0x1F1D1A).opacity(0.07)

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

/// The white floating card: radius 28, Apple-style soft elevation. The only content container.
private struct CardSurface: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: .rect(cornerRadius: 28))
            // Two shadows read as one: a tight contact shadow and a wide ambient one. Both very
            // soft — harsh shadows are the fastest way to stop feeling first-party.
            .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
    }
}

extension View {
    /// Default inner padding 20 (the brief's "inside cards 20–24").
    func cardSurface(padding: CGFloat = 20) -> some View {
        modifier(CardSurface(padding: padding))
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
