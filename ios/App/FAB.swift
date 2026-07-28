import SwiftUI

/// The clay glass floating action button — the one pop of colour on the group screens, and one of
/// only two glass elements there (the tab bar is the other). Adds an expense.
///
/// It says "Ny utgift" rather than being a bare plus. A circle with a plus in it was read as "add
/// a group" on the first run with a real person, which it has never been — and the accessibility
/// label alone does not help someone looking at the screen.
struct FAB: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .semibold))
                Text("Ny utgift")
                    .font(.headline)
            }
            .foregroundStyle(Color(hex: 0xFFF9F2))
            .padding(.horizontal, 22)
            .frame(height: 56)
        }
        .glassEffect(.regular.tint(Theme.clayBright).interactive(), in: .capsule)
    }
}
