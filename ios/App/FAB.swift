import SwiftUI

/// The floating action button: a pill that says what it does. "Lägg till utgift" is the thing
/// people do ten times for every group they create, so the button is that one thing and says so
/// in words — a bare plus was read as "add a group" on the first run with a real person, and the
/// menu that used to disambiguate it only did so *after* the tap. Creating and joining groups
/// live in the Grupper title bar now, where iOS users look for "new".
struct FAB: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Lägg till utgift", systemImage: "plus")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .frame(height: 52)
                .background(Theme.accent, in: .capsule)
                .shadow(color: Theme.accent.opacity(0.35), radius: 12, y: 6)
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("Lägg till utgift")
    }
}
