import SwiftUI

/// The palette and surfaces from `docs/mockup.html` (the `:root` tokens), in one place so no
/// view hardcodes a hex string. Warm cream, Anthropic-adjacent.
///
/// Content is opaque and calm; glass lives only on the control layer (tab bar, FAB, Spara). These
/// colours are the content layer — the cards, the ink, the sage/clay of the zero line.
enum Theme {
    static let cream = Color(hex: 0xF3EFE6)
    static let card = Color(hex: 0xFFFDF7)
    static let ink = Color(hex: 0x2A2620)
    static let secondary = Color(hex: 0x8A8377)
    /// You are owed. Positive.
    static let sage = Color(hex: 0x4F7D58)
    /// You owe. Warm, not alarm-red — owing a friend is not an error.
    static let clay = Color(hex: 0xC25E3C)
    /// The one pop of colour per screen: the FAB.
    static let clayBright = Color(hex: 0xD97757)
    static let espresso = Color(hex: 0x2E2A22)
    static let hairline = Color(red: 70/255, green: 60/255, blue: 40/255, opacity: 0.12)

    /// The colour an amount takes from its sign. Never the only carrier of meaning — every amount
    /// on screen also spells its direction in words.
    static func tint(forSign amountMinor: Int64) -> Color {
        if amountMinor > 0 { return sage }
        if amountMinor < 0 { return clay }
        return secondary
    }
}

/// The cream background with the three soft ambient washes from the mockup, so any glass placed on
/// top has warm colour to refract.
struct AmbientBackground: View {
    var body: some View {
        Theme.cream
            .overlay(alignment: .topLeading) {
                wash(Color(hex: 0xF8E9DC)).offset(x: -60, y: -120)
            }
            .overlay(alignment: .topTrailing) {
                wash(Color(hex: 0xEDF0E3)).offset(x: 60, y: 40)
            }
            .overlay(alignment: .bottom) {
                wash(Color(hex: 0xF6EBD9)).offset(y: 160)
            }
            .ignoresSafeArea()
    }

    private func wash(_ colour: Color) -> some View {
        RadialGradient(colors: [colour, colour.opacity(0)], center: .center, startRadius: 0, endRadius: 260)
            .frame(width: 520, height: 520)
            .blur(radius: 40)
    }
}

/// The warm-white card surface: radius 26, whisper shadow. The primary content container.
private struct CardSurface: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: .rect(cornerRadius: 26))
            .shadow(color: Color(red: 60/255, green: 45/255, blue: 25/255, opacity: 0.06), radius: 2, y: 1)
    }
}

extension View {
    func cardSurface(padding: CGFloat = 18) -> some View {
        modifier(CardSurface(padding: padding))
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
