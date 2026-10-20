import SwiftUI

extension Steven {

    /// The white card every list is made of (01, 08, 09): radius 8, faint shadow, 16 pt padding.
    struct Card<Content: View>: View {
        var padding: CGFloat = StevenMetric.cardPadding
        @ViewBuilder let content: Content

        var body: some View {
            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .stevenCardBackground()
        }
    }

    /// "Så här beräknar vi betalningar / Läs mer här" (10): an `i` on a tinted circle, a bold
    /// title and a faint second line, in a card.
    struct InfoCard: View {
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey
        var systemImage = "info.circle"

        var body: some View {
            Card {
                HStack(spacing: 16) {
                    Image(systemName: systemImage)
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(StevenColor.ink)
                        .frame(width: StevenMetric.iconCircle, height: StevenMetric.iconCircle)
                        .background(StevenColor.accentTint, in: .circle)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).stevenFont(.rowTitleBold).foregroundStyle(StevenColor.ink)
                        Text(subtitle).stevenFont(.rowTitle).foregroundStyle(StevenColor.faint)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// "OKT. 2026", "DELTAGARE" (06, 08, 11, 14): grey capitals with a hairline under the full width.
    struct SectionHeader: View {
        let title: Text

        init(_ title: LocalizedStringKey) { self.title = Text(title) }
        init(verbatim title: String) { self.title = Text(verbatim: title) }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                title
                    .stevenFont(.section)
                    .foregroundStyle(StevenColor.section)
                    .padding(.horizontal, StevenMetric.gutter)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                    .accessibilityAddTraits(.isHeader)
                Hairline()
            }
        }
    }

    /// A one-point line in the hairline colour, at the screen's real pixel width.
    struct Hairline: View {
        var color = StevenColor.hairline
        @Environment(\.displayScale) private var displayScale

        var body: some View {
            Rectangle().fill(color).frame(height: 1 / displayScale).frame(maxWidth: .infinity)
        }
    }

    /// The trailing half of a `ListRow` (05, 06, 11).
    enum RowTrailing {
        case chevron
        case value(String, chevron: Bool = true)
        case toggle(Binding<Bool>)
        case none
    }

    /// A 60 pt full-width list row: 24 pt outline icon (or any leading view, like your avatar on
    /// "Mina detaljer"), 17 pt title and a chevron, value or toggle. Wrap it in a `Button` or
    /// `NavigationLink` with `RowButtonStyle` for the pressed grey.
    struct ListRow<Leading: View>: View {
        let title: LocalizedStringKey
        var trailing: RowTrailing = .chevron
        var showsSeparator = true
        @ViewBuilder let leading: Leading

        var body: some View {
            HStack(spacing: 16) {
                leading
                    .frame(width: StevenMetric.listIcon + 4)
                Text(title)
                    .stevenFont(.rowTitle)
                    .foregroundStyle(StevenColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailingView
            }
            .padding(.horizontal, StevenMetric.gutter)
            .padding(.vertical, 8)
            .frame(minHeight: StevenMetric.rowHeight)
            .contentShape(.rect)
            .overlay(alignment: .bottom) {
                if showsSeparator { Hairline(color: StevenColor.rowSeparator) }
            }
        }

        @ViewBuilder private var trailingView: some View {
            switch trailing {
            case .chevron:
                Chevron()
            case .value(let value, let chevron):
                HStack(spacing: 12) {
                    Text(verbatim: value).stevenFont(.rowTitle).foregroundStyle(StevenColor.muted)
                    if chevron { Chevron() }
                }
            case .toggle(let isOn):
                Toggle("", isOn: isOn).labelsHidden().tint(StevenColor.accentFill)
            case .none:
                EmptyView()
            }
        }
    }

    /// `chevron.right` in 17 pt light (§2.4).
    struct Chevron: View {
        var body: some View {
            Image(systemName: "chevron.right")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(StevenColor.ink)
                .accessibilityHidden(true)
        }
    }

    /// The grey a list row turns while pressed (05).
    struct RowButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .background(configuration.isPressed ? StevenColor.pressed : StevenColor.surface)
        }
    }

    /// "Namn — Carl Bedrot" (07): grey label left, value right, 55 pt, inset hairline under.
    /// Use inside a `Card(padding: 0)`.
    struct FormRow<Value: View>: View {
        let label: LocalizedStringKey
        var showsSeparator = true
        @ViewBuilder let value: Value

        var body: some View {
            HStack(spacing: 16) {
                Text(label).stevenFont(.rowTitle).foregroundStyle(StevenColor.label)
                Spacer(minLength: 8)
                value
            }
            .padding(.vertical, 8)
            .frame(minHeight: StevenMetric.formRowHeight)
            .padding(.horizontal, StevenMetric.gutter)
            .overlay(alignment: .bottom) {
                if showsSeparator {
                    Hairline().padding(.horizontal, StevenMetric.gutter)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

extension Steven.ListRow where Leading == Steven.ListIcon {
    init(icon: String, title: LocalizedStringKey, trailing: Steven.RowTrailing = .chevron, showsSeparator: Bool = true) {
        self.init(title: title, trailing: trailing, showsSeparator: showsSeparator) {
            Steven.ListIcon(systemName: icon)
        }
    }
}

extension Steven.FormRow where Value == Steven.FormValue {
    init(label: LocalizedStringKey, value: String, showsSeparator: Bool = true) {
        self.init(label: label, showsSeparator: showsSeparator) { Steven.FormValue(text: value) }
    }
}

extension Steven {
    /// A 24 pt outline SF Symbol (§2.4).
    struct ListIcon: View {
        let systemName: String

        var body: some View {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(StevenColor.ink)
                .accessibilityHidden(true)
        }
    }

    struct FormValue: View {
        let text: String

        var body: some View {
            Text(verbatim: text)
                .stevenFont(.rowTitle)
                .foregroundStyle(StevenColor.inkSoft)
                .multilineTextAlignment(.trailing)
        }
    }
}

extension View {
    /// The card surface on its own, for views that lay out their own padding.
    func stevenCardBackground() -> some View {
        background(
            StevenColor.surface
                .clipShape(.rect(cornerRadius: StevenMetric.cardRadius))
                .stevenShadow(.card)
        )
    }
}

#Preview("Surfaces – light") { StevenSurfacesPreview() }
#Preview("Surfaces – dark") { StevenSurfacesPreview().preferredColorScheme(.dark) }

private struct StevenSurfacesPreview: View {
    @State private var on = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Steven.InfoCard(title: "Så här beräknar vi betalningar", subtitle: "Läs mer här")
                    .padding(StevenMetric.gutter)
                Steven.SectionHeader(verbatim: "OKT. 2026")
                Steven.ListRow(icon: "questionmark.square", title: "Hjälpcenter")
                Steven.ListRow(icon: "square.and.arrow.up", title: "Dela till en vän", trailing: .toggle($on))
                Steven.Card(padding: 0) {
                    VStack(spacing: 0) {
                        Steven.FormRow(label: "Namn", value: "Carl Bedrot")
                        Steven.FormRow(label: "Telefon", value: "070-123 45 67", showsSeparator: false)
                    }
                }
                .padding(StevenMetric.gutter)
            }
        }
        .background(StevenColor.screen)
    }
}
