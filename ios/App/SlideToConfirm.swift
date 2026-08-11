import SwiftUI

/// A deliberate gesture for the one action that writes money into the books.
///
/// Buttons are for things that can be shrugged off; recording a payment is an attestation —
/// "this money moved" — that stands in front of the payee until answered (design doc, M8). The
/// drag is the weight: something you perform, not a target you graze on the way to dismissing
/// a sheet. The ritual must never gate accessibility, so VoiceOver users get the same action
/// as a plain button, and with Reduce Motion on a tap works too.
struct SlideToConfirm: View {
    let label: String
    var fill: Color = Theme.ink
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var dragX: CGFloat = 0
    @State private var completed = false

    private let height: CGFloat = 56

    var body: some View {
        GeometryReader { geometry in
            let travel = geometry.size.width - height + 8
            let offset = completed ? travel : min(max(dragX, 0), travel)
            ZStack(alignment: .leading) {
                Capsule().fill(fill)
                Text(label)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    // Gone by two-thirds of the way — the label is an instruction, and by then
                    // the person is already following it.
                    .opacity(1 - Double(offset / max(travel, 1)) * 1.5)
                Circle()
                    .fill(.white)
                    .overlay {
                        Image(systemName: "arrow.right")
                            .font(.body.weight(.bold))
                            .foregroundStyle(fill)
                    }
                    .padding(4)
                    .offset(x: offset)
                    .animation(.spring(duration: 0.3), value: offset)
                    .gesture(drag(travel: travel))
            }
        }
        .frame(height: height)
        .contentShape(.capsule)
        .onTapGesture {
            // Reduce Motion opted out of theatre, not of paying — a tap is enough there.
            guard reduceMotion, !completed else { return }
            completed = true
            action()
        }
        .accessibilityRepresentation {
            Button(label, action: action)
        }
    }

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture()
            .updating($dragX) { value, state, _ in
                state = value.translation.width
            }
            .onEnded { value in
                // Four fifths of the track is commitment; anything less springs back to
                // "nothing happened", which is exactly what the ledger should think too.
                guard value.translation.width > travel * 0.8, !completed else { return }
                completed = true
                action()
            }
    }
}
