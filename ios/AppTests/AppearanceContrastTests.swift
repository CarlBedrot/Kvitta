import SwiftUI
import UIKit
import Testing
@testable import Kvitta

@MainActor
struct AppearanceContrastTests {
    @Test func neutralTextRemainsReadableInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for surface in [Theme.bg, Theme.card] {
                for text in [Theme.ink, Theme.secondary] {
                    #expect(contrast(text, surface, style: style) >= 4.5)
                }
            }
        }
    }

    /// README §2.1/§6.3 and #145: body text at AAA, accent text at AA, in both modes, on every
    /// Steven surface text sits on.
    @Test func stevenTextMeetsItsContrastFloorsInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for surface in [StevenColor.surface, StevenColor.screen, StevenColor.content] {
                #expect(contrast(StevenColor.ink, surface, style: style) >= 7, "ink, \(style.rawValue)")
                #expect(contrast(StevenColor.inkSoft, surface, style: style) >= 7, "inkSoft, \(style.rawValue)")
                #expect(contrast(StevenColor.accent, surface, style: style) >= 4.5, "accent, \(style.rawValue)")
            }
        }
    }

    /// The initials sit on a pastel plate; they must stay readable on every one of them.
    @Test func stevenInitialsAreReadableOnEveryPastel() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for pastel in StevenColor.avatarPastels {
                #expect(contrast(StevenColor.ink, pastel, style: style) >= 4.5)
            }
        }
    }

    /// The README's measured values, so a token cannot drift from the reference unnoticed.
    @Test func stevenLightTokensMatchTheReference() {
        let expected: [(Color, UInt32)] = [
            (StevenColor.screen, 0xFAFAFB), (StevenColor.content, 0xF9F9FA), (StevenColor.surface, 0xFFFFFF),
            (StevenColor.hairline, 0xDBDBDD), (StevenColor.ink, 0x3A3C4A), (StevenColor.muted, 0x9FA1AC),
            (StevenColor.accent, 0x1A75B8), (StevenColor.accentFill, 0x4FA9E8), (StevenColor.owe, 0xFECCB5),
            (StevenColor.badge, 0xFF383C), (StevenColor.chip, 0xEBEBEC),
        ]
        for (color, hex) in expected {
            #expect(rgb(color, style: .light) == hex)
        }
        #expect(rgb(StevenColor.screen, style: .dark) == 0x121214)
        #expect(rgb(StevenColor.surface, style: .dark) == 0x1F1F23)
        #expect(rgb(StevenColor.accent, style: .dark) == 0x6BB8EE)
    }

    private func rgb(_ color: Color, style: UIUserInterfaceStyle) -> UInt32 {
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &alpha)
        func byte(_ c: CGFloat) -> UInt32 { UInt32((c * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    private func contrast(_ a: Color, _ b: Color, style: UIUserInterfaceStyle) -> Double {
        let traits = UITraitCollection(userInterfaceStyle: style)
        func luminance(_ color: Color) -> Double {
            let resolved = UIColor(color).resolvedColor(with: traits)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
            resolved.getRed(&r, green: &g, blue: &b, alpha: &alpha)
            let linear = [r, g, b].map { component -> Double in
                let value = Double(component)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        let first = luminance(a), second = luminance(b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}
