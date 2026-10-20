import SwiftUI

extension Steven {

    /// "Påminn", "LOGGA UT" (01, 07, 08): accent text in a 1.5 pt accent outline, radius 6.
    struct OutlineButtonStyle: ButtonStyle {
        var height: CGFloat = StevenMetric.buttonHeight
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            let tint = isEnabled ? StevenColor.accent : StevenColor.accentDisabled
            configuration.label
                .stevenFont(.rowTitleBold)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(
                    configuration.isPressed ? StevenColor.pressed : StevenColor.surface,
                    in: .rect(cornerRadius: StevenMetric.controlRadius)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: StevenMetric.controlRadius)
                        .strokeBorder(tint, lineWidth: StevenMetric.outlineWidth)
                }
                .contentShape(.rect)
        }
    }

    /// "Nästa", "Spara", "Betala" (12, 14): white bold text on the accent fill, radius 6. Lighter
    /// while disabled, the way Nästa waits for an amount.
    struct FilledButtonStyle: ButtonStyle {
        var height: CGFloat = StevenMetric.buttonHeight
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .stevenFont(.rowTitleBold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(
                    isEnabled ? StevenColor.accentFill : StevenColor.accentDisabled,
                    in: .rect(cornerRadius: StevenMetric.controlRadius)
                )
                .opacity(configuration.isPressed ? 0.8 : 1)
                .contentShape(.rect)
        }
    }

    /// The 60 pt add button (08): accent-filled circle, thin dark plus, lifted by its shadow.
    struct FAB: View {
        var accessibilityLabel: LocalizedStringKey = "Lägg till utgift"
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(StevenColor.onAccentFill)
                    .frame(width: StevenMetric.fab, height: StevenMetric.fab)
                    .background(StevenColor.accentFill, in: .circle)
                    .stevenShadow(.fab)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(accessibilityLabel))
        }
    }

    /// The rounded accent square with a white tick (14). Unticked it is an empty outline.
    struct CheckBox: View {
        @Binding var isOn: Bool
        var accessibilityLabel: Text = Text(verbatim: "")

        var body: some View {
            Button {
                isOn.toggle()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: StevenMetric.controlRadius)
                        .fill(isOn ? StevenColor.accentFill : StevenColor.surface)
                    RoundedRectangle(cornerRadius: StevenMetric.controlRadius)
                        .strokeBorder(isOn ? Color.clear : StevenColor.muted, lineWidth: StevenMetric.outlineWidth)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: StevenMetric.checkBox, height: StevenMetric.checkBox)
                .frame(width: StevenMetric.minimumHitTarget, height: StevenMetric.minimumHitTarget)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isOn ? [.isSelected] : [])
        }
    }

    /// One chip in a `ChipRow`.
    struct Chip<ID: Hashable>: Identifiable {
        let id: ID
        let title: String
    }

    /// Category chips in a horizontal row (14): grey, the selected one white with a shadow and
    /// bold text, `…` last for the full list.
    struct ChipRow<ID: Hashable>: View {
        let chips: [Chip<ID>]
        @Binding var selection: ID?
        var onMore: (() -> Void)?

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(chips) { chip in
                        let selected = chip.id == selection
                        Button {
                            selection = chip.id
                        } label: {
                            Text(verbatim: chip.title)
                                .stevenFont(selected ? .rowTitleBold : .rowTitle)
                                .modifier(ChipShape(selected: selected))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                    }
                    if let onMore {
                        Button(action: onMore) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .bold))
                                .padding(.horizontal, 6)
                                .modifier(ChipShape(selected: false))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Fler kategorier"))
                    }
                }
                .padding(.horizontal, StevenMetric.gutter)
                .padding(.vertical, 6)
            }
        }
    }

    private struct ChipShape: ViewModifier {
        let selected: Bool

        func body(content: Content) -> some View {
            content
                .foregroundStyle(StevenColor.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: StevenMetric.controlRadius)
                            .fill(StevenColor.surface)
                            .stevenShadow(.chip)
                    } else {
                        RoundedRectangle(cornerRadius: StevenMetric.controlRadius)
                            .fill(StevenColor.chip)
                    }
                }
                .padding(.vertical, 5)
                .contentShape(.rect)
        }
    }

    /// A key on the `Keypad`.
    enum Key: Hashable, Sendable {
        case digit(Int)
        case decimal
        case delete
    }

    /// The 3×4 amount keypad (12, 13): 1–9, `,`, 0, ⌫ on white, divided by hairlines. It only
    /// reports keys; the caller keeps the amount as an integer string in minor units.
    struct Keypad: View {
        let onKey: (Key) -> Void

        private static let rows: [[Key]] = [
            [.digit(1), .digit(2), .digit(3)],
            [.digit(4), .digit(5), .digit(6)],
            [.digit(7), .digit(8), .digit(9)],
            [.decimal, .digit(0), .delete],
        ]

        var body: some View {
            VStack(spacing: 0) {
                ForEach(Self.rows.indices, id: \.self) { row in
                    Hairline()
                    HStack(spacing: 0) {
                        ForEach(Self.rows[row].indices, id: \.self) { column in
                            if column > 0 {
                                Rectangle().fill(StevenColor.hairline).frame(width: 1)
                            }
                            key(Self.rows[row][column])
                        }
                    }
                    .frame(height: StevenMetric.keypadRowHeight)
                }
            }
            .background(StevenColor.surface)
        }

        private func key(_ key: Key) -> some View {
            Button {
                onKey(key)
            } label: {
                label(for: key)
                    .foregroundStyle(StevenColor.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
            }
            .buttonStyle(KeyStyle())
            .accessibilityLabel(accessibilityLabel(for: key))
        }

        @ViewBuilder private func label(for key: Key) -> some View {
            switch key {
            case .digit(let digit):
                Text(verbatim: "\(digit)").stevenFont(.keypad)
            case .decimal:
                Text(verbatim: ",").stevenFont(.keypad)
            case .delete:
                Image(systemName: "delete.left")
                    .font(.system(size: 22, weight: .semibold))
            }
        }

        private func accessibilityLabel(for key: Key) -> Text {
            switch key {
            case .digit(let digit): Text(verbatim: "\(digit)")
            case .decimal: Text("Decimalkomma")
            case .delete: Text("Radera")
            }
        }

        private struct KeyStyle: ButtonStyle {
            func makeBody(configuration: Configuration) -> some View {
                configuration.label
                    .background(configuration.isPressed ? StevenColor.pressed : StevenColor.surface)
            }
        }
    }
}

#Preview("Controls – light") { StevenControlsPreview() }
#Preview("Controls – dark") { StevenControlsPreview().preferredColorScheme(.dark) }

private struct StevenControlsPreview: View {
    @State private var ticked = true
    @State private var category: String? = "taxi"

    var body: some View {
        VStack(spacing: 20) {
            Steven.ChipRow(
                chips: [.init(id: "taxi", title: "Taxi"), .init(id: "shop", title: "Shopping"), .init(id: "bar", title: "Bar")],
                selection: $category,
                onMore: {}
            )
            HStack {
                Steven.CheckBox(isOn: $ticked)
                Steven.CheckBox(isOn: .constant(false))
                Steven.FAB {}
            }
            Button("Påminn") {}.buttonStyle(Steven.OutlineButtonStyle())
            Button("Spara") {}.buttonStyle(Steven.FilledButtonStyle())
            Button("Nästa") {}.buttonStyle(Steven.FilledButtonStyle()).disabled(true)
            Spacer()
            Steven.Keypad { _ in }
        }
        .padding(.top)
        .background(StevenColor.surface)
    }
}
