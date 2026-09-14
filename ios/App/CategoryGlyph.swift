import SwiftUI

/// The leading mark on an expense: its category's symbol in the system's fill circle.
struct CategoryGlyph: View {
    let categoryId: String
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: Categories.symbol(for: categoryId))
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(Color(.tertiarySystemFill), in: .circle)
            .accessibilityHidden(true)
    }
}
