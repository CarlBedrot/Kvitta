import SwiftUI
import UIKit
import KvittaCore

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

    /// The brand blue — the same sky the mascot sits on in the icon and on the launch screen, so
    /// the app is one colour from the home screen inward. The FAB, primary buttons, the selected
    /// tab — and nothing else, so the single pop of colour keeps meaning "the main thing to do
    /// here". Identical in both halves.
    static let accent = Color(hex: 0x4FA9E8)

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

    // MARK: Group identity

    /// The colour a group wears when it has no photo: a wash behind its badge, and a faint tint
    /// on its hero card. Chosen by the group's id, so a group is the same colour on every phone
    /// and after every reinstall without anyone picking it — and two groups side by side stop
    /// looking like the same grey circle with different letters in it.
    ///
    /// Eight warm tones only. Nothing blue, because blue is the accent and means "do this";
    /// nothing as green as `positiveWash`, because that green means "settled". Each tone is a
    /// pair per half: the wash the badge sits on, and the deeper voice of the same hue the
    /// initials are written in. Contrast of initials on wash, light / dark:
    /// peach 5.27 / 7.81 · rose 5.08 / 7.45 · mauve 5.52 / 7.40 · honey 5.35 / 6.96 ·
    /// olive 5.01 / 7.36 · sand 5.16 / 7.06 · terracotta 4.69 / 7.19 · plum 5.63 / 6.71.
    /// The hero tint is the wash at 45% over the card of its half; ink stays above 11:1 on
    /// every one of them, so the card is coloured without the numbers paying for it.
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
            GroupTint(wash: (0xF7DFC9, 0x4A3120), foreground: (0x8A4B1E, 0xF2C9A5), hero: (0xFBF1E7, 0x34271D)), // peach
            GroupTint(wash: (0xF7D6D6, 0x4A2626), foreground: (0x9A3B3B, 0xF0B4B4), hero: (0xFBEDED, 0x342220)), // rose
            GroupTint(wash: (0xEBDDF0, 0x3E2E44), foreground: (0x6E4A7A, 0xD9BEE3), hero: (0xF6F0F8, 0x2F262D)), // mauve
            GroupTint(wash: (0xF7EBC4, 0x4A3E1A), foreground: (0x7A5A10, 0xEAD08A), hero: (0xFBF6E4, 0x342D1B)), // honey
            GroupTint(wash: (0xE6E7C8, 0x3A3B22), foreground: (0x5E6420, 0xD0D39A), hero: (0xF4F4E6, 0x2D2C1E)), // olive
            GroupTint(wash: (0xEDE3D2, 0x3F372B), foreground: (0x6F5A3A, 0xD8C7A8), hero: (0xF7F2EB, 0x2F2A22)), // sand
            GroupTint(wash: (0xF3D6CB, 0x4B2C22), foreground: (0x96482E, 0xEDB9A6), hero: (0xFAEDE8, 0x34251E)), // terracotta
            GroupTint(wash: (0xE9D8E0, 0x44303C), foreground: (0x7C3F5E, 0xDDB6CB), hero: (0xF5EDF1, 0x31272A)), // plum
        ]

        /// Which of the eight a group gets. Over the id's raw bytes rather than `hashValue`,
        /// which Swift seeds differently on every launch — a colour that changed each time the
        /// app opened would be worse than no colour at all.
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

    // MARK: The attestation control

    /// The track of `SlideToConfirm`, and whatever it carries.
    ///
    /// The control used to be `ink` with a white label — a pairing that only works by day. At
    /// night `ink` is the cream, and white on cream is 1.16:1: the one gesture in the app that
    /// writes money into the books became an unlabelled bar. The fix is not a different colour
    /// but a *pair*: the fill is still the ink of its half, and the label is always the ground of
    /// that half — white by day (16.81:1), the deep warm black by night (16.01:1 on the cream).
    /// Both halves end up with more contrast than a button ever had, and the control keeps
    /// reading as the heaviest object on the sheet, which is the point of it.
    static let controlFill = ink
    /// What sits on `controlFill`: the label, and the knob. Never `.white` — that is the light
    /// half's value leaking into the dark one, which is exactly the bug this token retires.
    static let controlLabel = adaptive(light: 0xFFFFFF, dark: 0x151310)

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
/// The prompt text inside a text field. The system draws placeholders in its own tertiary grey,
/// which lands at 2.6:1 on a white row by day and 3.0:1 on a card by night — the "what am I
/// supposed to type here" hint was the least readable text on the screen. `Theme.secondary`
/// clears 4.5:1 in both halves (5.4:1 on the light card, 6.0:1 on the dark one) and is still
/// visibly not the typed value, which is the only other thing a placeholder has to be.
extension Text {
    func placeholderStyle() -> Text {
        foregroundStyle(Theme.secondary)
    }
}

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

/// The primary action: accent fill, white text, radius 22, gentle press scale. With a quiet
/// fill and ink label it is the secondary twin beside a primary — same shape, less voice.
struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = Theme.accent
    var label: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(label)
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
