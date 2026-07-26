import SwiftUI

/// The app's one visualization: a balance on a horizontal axis centred at zero. The bar extends
/// right (sage) when you are owed, left (clay) when you owe. At zero the bar collapses to the
/// centre tick. Opaque content-layer element — never glass.
///
/// `scaleMinor` is the magnitude that fills a full half of the track, so a row of these share a
/// scale and read against each other. Purely presentational: it carries no meaning on its own
/// (it is hidden from VoiceOver), which is why every caller pairs it with the amount in words.
struct ZeroLine: View {
    let amountMinor: Int64
    let scaleMinor: Int64
    var mini: Bool = false

    private var barHeight: CGFloat { mini ? 5 : 8 }
    private var frameHeight: CGFloat { mini ? 9 : 14 }
    private var tickHeight: CGFloat { mini ? 9 : 14 }

    private var fraction: CGFloat {
        guard scaleMinor > 0 else { return 0 }
        return min(1, CGFloat(abs(amountMinor)) / CGFloat(scaleMinor))
    }

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            ZStack {
                Capsule().fill(Theme.hairline).frame(height: barHeight)

                HStack(spacing: 0) {
                    Color.clear.frame(width: half).overlay(alignment: .trailing) {
                        if amountMinor < 0 {
                            Capsule().fill(Theme.clayBright).frame(width: half * fraction, height: barHeight)
                        }
                    }
                    Color.clear.frame(width: half).overlay(alignment: .leading) {
                        if amountMinor > 0 {
                            Capsule().fill(Theme.sage).frame(width: half * fraction, height: barHeight)
                        }
                    }
                }

                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(hex: 0xC9C0B0))
                    .frame(width: 2, height: tickHeight)
            }
        }
        .frame(height: frameHeight)
        .accessibilityHidden(true)
    }
}
