import SwiftUI

/// The clay glass floating action button — the one pop of colour on the home screen, and one of
/// only two glass elements there (the tab bar is the other). Adds an expense.
struct FAB: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Color(hex: 0xFFF9F2))
                .frame(width: 62, height: 62)
        }
        .glassEffect(.regular.tint(Theme.clayBright).interactive(), in: .circle)
        .accessibilityLabel("Ny utgift")
    }
}
