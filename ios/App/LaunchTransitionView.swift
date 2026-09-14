import SwiftUI

/// Fills the one gap where an animation is possible at all: the static `UILaunchScreen` cannot
/// move (it is UIKit scene setup with no app code running, `Bootstrap.run`'s note), but the frame
/// right after it can. This shows the same mascot on the same background the launch screen
/// already used and crossfades into `content`, so the handoff reads as one continuous moment
/// instead of a cut. Nothing else: the bounce that used to greet a first launch was a second
/// of the app performing at you before it had shown you anything.
///
/// A tap skips straight to `content` — nobody should be made to wait on a fade.
struct LaunchTransitionView<Content: View>: View {
    private let content: Content

    @State private var revealed = false

    init(@ViewBuilder content: () -> Content) {
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
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { reveal() }
                    .transition(.opacity)
                    .accessibilityHidden(true)
                    .task { reveal() }
            }
        }
    }

    private func reveal() {
        guard !revealed else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            revealed = true
        }
    }
}
