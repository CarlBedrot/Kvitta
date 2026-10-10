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
