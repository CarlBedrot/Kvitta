import SwiftUI

/// The one moment this app is allowed to be loud.
///
/// Being square with everyone is the state Slice is always working toward, and until now reaching
/// it changed a card's wording and nothing else — the app's only good news arrived as quietly as a
/// validation error. A burst of paper is the difference between an app that reports a state and one
/// that is pleased for you.
///
/// Deliberately not a package: forty rectangles falling is not a dependency. It draws nothing until
/// it is fired, takes no hit testing ever, and clears itself when the last piece is off screen.
struct ConfettiBurst: View {
    /// Bump to fire. An `Int` rather than a `Bool` so a second celebration in the same session
    /// still fires — a toggle that is already true is a burst nobody sees.
    let trigger: Int

    @State private var pieces: [Piece] = []
    @State private var fallen = false
    /// Motion sensitivity is not a preference to work around. The haptic and the wording still
    /// land; only the flying paper is withheld.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(piece.colour)
                        .frame(width: piece.width, height: piece.width * 1.7)
                        .rotationEffect(.degrees(fallen ? piece.spin : 0))
                        .offset(
                            x: geometry.size.width * piece.start + (fallen ? piece.drift : 0),
                            y: fallen ? geometry.size.height + 60 : -40
                        )
                        .animation(
                            .easeIn(duration: piece.duration).delay(piece.delay),
                            value: fallen
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in burst() }
    }

    private func burst() {
        guard !reduceMotion else { return }

        pieces = (0..<44).map { _ in Piece() }
        fallen = false
        // One runloop turn between "the pieces exist at the top" and "they are falling", or
        // SwiftUI sees a single insertion at the end state and there is nothing to animate.
        DispatchQueue.main.async { fallen = true }

        let longest = pieces.map { $0.delay + $0.duration }.max() ?? 0
        Task {
            try? await Task.sleep(for: .seconds(longest + 0.1))
            pieces = []
        }
    }

    struct Piece: Identifiable {
        let id = UUID()
        /// Where it enters, as a fraction of the width.
        let start = CGFloat.random(in: 0...0.96)
        /// How far sideways it wanders on the way down. Paper does not fall straight.
        let drift = CGFloat.random(in: -70...70)
        let width = CGFloat.random(in: 5...9)
        let spin = Double.random(in: -540...540)
        let delay = Double.random(in: 0...0.45)
        let duration = Double.random(in: 1.5...2.6)
        /// The app's own palette plus two festive outsiders, so it reads as this app celebrating
        /// rather than a generic party effect pasted on top.
        let colour = [
            Theme.accent,
            Theme.positive,
            Color(hex: 0xF2C14E),
            Color(hex: 0x4FA9E8),
            Color(hex: 0xE0643C),
        ].randomElement()!
    }
}
