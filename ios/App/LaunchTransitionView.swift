import SwiftUI

/// Fills the one gap where an animation is possible at all: the static `UILaunchScreen` cannot
/// move (it is UIKit scene setup with no app code running, `Bootstrap.run`'s note), but the frame
/// right after it can. This shows the same mascot on the same brand blue the launch screen already
/// used, holds it for a beat, then crossfades into `content` — so the handoff reads as one
/// continuous moment instead of a cut.
///
/// First launch (an empty ledger — genuinely the first time this device has opened the app) gets
/// a short bounce, the mascot settling like dough landing. Every launch after that skips straight
/// to the crossfade: a daily user should never wait on this. `accessibilityReduceMotion` collapses
/// both to a plain fade, the same accommodation `ConfettiBurst` makes for the same reason.
///
/// A tap skips straight to `content` — "avbrytbar" in the ticket. Nobody should be made to sit
/// through this twice just because they tapped Grupper before it finished.
struct LaunchTransitionView<Content: View>: View {
    private let content: Content
    private let playFullAnimation: Bool

    @State private var revealed = false
    @State private var mascotScale: CGFloat = 0.6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(playFullAnimation: Bool, @ViewBuilder content: () -> Content) {
        self.playFullAnimation = playFullAnimation
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
                .opacity(revealed ? 1 : 0)

            if !revealed {
                Color("LaunchBackground")
                    .ignoresSafeArea()
                    .overlay {
                        Image("LaunchLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 160)
                            .scaleEffect(mascotScale)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { reveal() }
                    .transition(.opacity)
                    .accessibilityHidden(true)
                    .task { await play() }
            }
        }
    }

    private func play() async {
        guard !reduceMotion, playFullAnimation else {
            // Every launch but the first: no artificial wait, just the crossfade below.
            reveal()
            return
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
            mascotScale = 1.08
        }
        try? await Task.sleep(for: .seconds(0.32))
        guard !revealed else { return }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
            mascotScale = 1.0
        }
        try? await Task.sleep(for: .seconds(0.38))
        guard !revealed else { return }

        reveal()
    }

    private func reveal() {
        guard !revealed else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            revealed = true
        }
    }
}
