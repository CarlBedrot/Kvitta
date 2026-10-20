import SwiftUI

extension Steven {

    /// "Grupper" left, "Ny grupp +" right in accent (01, 04). The action is optional — Notiser
    /// puts "Läs alla" there without a plus.
    struct ScreenHeader: View {
        let title: LocalizedStringKey
        var actionTitle: LocalizedStringKey?
        var actionShowsPlus = true
        var action: (() -> Void)?

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .stevenFont(.screenTitle)
                    .foregroundStyle(StevenColor.inkSoft)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let actionTitle, let action {
                    Button(action: action) {
                        HStack(alignment: .center, spacing: 8) {
                            Text(actionTitle).stevenFont(.cardTitle).fontWeight(.regular)
                            if actionShowsPlus {
                                Image(systemName: "plus")
                                    .font(.system(size: 30, weight: .ultraLight))
                                    .accessibilityHidden(true)
                            }
                        }
                        .foregroundStyle(StevenColor.accent)
                        .frame(minHeight: StevenMetric.minimumHitTarget)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, StevenMetric.gutter + 4)
            .padding(.vertical, 8)
        }
    }

    /// The leading control of a `NavTitleBar`.
    enum NavLeading {
        case back(() -> Void)
        case close(() -> Void)
        case none
    }

    /// The trailing control of a `NavTitleBar`: an accent text button ("Ändra") or `•••`.
    enum NavTrailing {
        case text(LocalizedStringKey, () -> Void)
        case more(() -> Void)
        case none
    }

    /// A centred capital title between `‹`/`✕` and an accent action, hairline under (07, 11, 12, 15).
    struct NavTitleBar<Title: View>: View {
        var leading: NavLeading = .none
        var trailing: NavTrailing = .none
        var showsHairline = true
        @ViewBuilder let title: Title

        var body: some View {
            ZStack {
                title
                    .stevenFont(.navTitle)
                    .foregroundStyle(StevenColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 72)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    leadingButton
                    Spacer()
                    trailingButton
                }
                .padding(.horizontal, 6)
            }
            .frame(minHeight: StevenMetric.navBarHeight)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) {
                if showsHairline { Hairline(color: StevenColor.rowSeparator) }
            }
        }

        @ViewBuilder private var leadingButton: some View {
            switch leading {
            case .back(let action):
                IconButton(systemName: "chevron.left", label: "Tillbaka", action: action)
            case .close(let action):
                IconButton(systemName: "xmark", label: "Stäng", action: action)
            case .none:
                EmptyView()
            }
        }

        @ViewBuilder private var trailingButton: some View {
            switch trailing {
            case .text(let label, let action):
                Button(action: action) {
                    Text(label)
                        .stevenFont(.rowTitleBold)
                        .foregroundStyle(StevenColor.accent)
                        .padding(.horizontal, 10)
                        .frame(minHeight: StevenMetric.minimumHitTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            case .more(let action):
                IconButton(systemName: "ellipsis", label: "Mer", weight: .bold, size: 20, action: action)
            case .none:
                EmptyView()
            }
        }
    }

    /// A light 24 pt glyph with a 44 pt target (§2.4).
    struct IconButton: View {
        let systemName: String
        let label: LocalizedStringKey
        var weight: Font.Weight = .light
        var size: CGFloat = 24
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: size, weight: weight))
                    .foregroundStyle(StevenColor.ink)
                    .frame(width: StevenMetric.minimumHitTarget, height: StevenMetric.minimumHitTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(label))
        }
    }

    /// UTGIFTER · STÄLLNING · BETALNINGAR (08–10): equal-width capital tabs, the selected one in
    /// ink over a 3 pt accent line, a hairline under the whole row.
    struct UnderlineTabs<Tab: Hashable>: View {
        @Binding var selection: Tab
        let tabs: [(tab: Tab, title: LocalizedStringKey)]
        @Namespace private var underline

        var body: some View {
            HStack(spacing: 0) {
                ForEach(tabs.indices, id: \.self) { index in
                    let item = tabs[index]
                    let selected = item.tab == selection
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { selection = item.tab }
                    } label: {
                        Text(item.title)
                            .stevenFont(.tab)
                            .foregroundStyle(selected ? StevenColor.ink : StevenColor.tabInactive)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, minHeight: StevenMetric.tabRowHeight)
                            .contentShape(.rect)
                            .overlay(alignment: .bottom) {
                                if selected {
                                    Rectangle()
                                        .fill(StevenColor.accentFill)
                                        .frame(height: StevenMetric.tabUnderline)
                                        .matchedGeometryEffect(id: "underline", in: underline)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
            .overlay(alignment: .bottom) { Hairline().offset(y: 1) }
        }
    }

    /// The three tabs of decision 6.1.
    enum RootTab: Hashable, CaseIterable {
        case groups, notifications, more

        var title: LocalizedStringKey {
            switch self {
            case .groups: "Grupper"
            case .notifications: "Notiser"
            case .more: "Mer"
            }
        }

        func systemImage(selected: Bool) -> String {
            switch self {
            case .groups: selected ? "person.2.fill" : "person.2"
            case .notifications: selected ? "bell.fill" : "bell"
            case .more: "ellipsis"
            }
        }
    }

    /// White tab bar with a hairline on top, filled accent icon for the selected tab, a red
    /// badge on Notiser (01, 04, 05).
    struct TabBar: View {
        @Binding var selection: RootTab
        var badges: [RootTab: Int] = [:]

        var body: some View {
            HStack(spacing: 0) {
                ForEach(RootTab.allCases, id: \.self) { tab in
                    item(tab)
                }
            }
            .padding(.top, 6)
            .background {
                StevenColor.surface.ignoresSafeArea(edges: .bottom)
            }
            .overlay(alignment: .top) { Hairline() }
        }

        private func item(_ tab: RootTab) -> some View {
            let selected = tab == selection
            let count = badges[tab] ?? 0
            return Button {
                selection = tab
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: tab.systemImage(selected: selected))
                        .font(.system(size: 24, weight: tab == .more ? .bold : .light))
                        .frame(height: 30)
                        .overlay(alignment: .topTrailing) {
                            if count > 0 { Badge(count: count).offset(x: 22, y: -6) }
                        }
                    Text(tab.title).stevenFont(.tabBar)
                }
                .foregroundStyle(selected ? StevenColor.accent : StevenColor.tabInactive)
                .frame(maxWidth: .infinity, minHeight: 49)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityValue(count > 0 ? Text("\(count) olästa") : Text(verbatim: ""))
        }
    }

    /// The red count bubble on a tab.
    struct Badge: View {
        let count: Int

        var body: some View {
            Text(verbatim: count > 999 ? "999+" : "\(count)")
                .font(.system(size: 15, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 22, minHeight: 20)
                .background(StevenColor.badge, in: .capsule)
                .fixedSize()
                .accessibilityHidden(true)
        }
    }
}

extension Steven.NavTitleBar where Title == Text {
    init(title: LocalizedStringKey, leading: Steven.NavLeading = .none, trailing: Steven.NavTrailing = .none) {
        self.init(leading: leading, trailing: trailing) { Text(title) }
    }
}

#Preview("Navigation – light") { StevenNavigationPreview() }
#Preview("Navigation – dark") { StevenNavigationPreview().preferredColorScheme(.dark) }

private struct StevenNavigationPreview: View {
    @State private var tab = 0
    @State private var root = Steven.RootTab.groups

    var body: some View {
        VStack(spacing: 24) {
            Steven.ScreenHeader(title: "Grupper", actionTitle: "Ny grupp", action: {})
            Steven.NavTitleBar(title: "Inställningar", leading: .back({}), trailing: .text("Ändra", {}))
            Steven.UnderlineTabs(selection: $tab, tabs: [(0, "Utgifter"), (1, "Ställning"), (2, "Betalningar")])
            Spacer()
            Steven.TabBar(selection: $root, badges: [.notifications: 495])
        }
        .background(StevenColor.screen)
    }
}
