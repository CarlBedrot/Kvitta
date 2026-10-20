#if DEBUG
import SwiftUI
import KvittaCore

/// DEBUG-only: the Steven components composed the way each reference screenshot uses them, so a
/// simulator screenshot can sit next to the reference (#145 evidence). Launch with
/// `-StevenGallery 08` (any page id below) to open a page instead of the app. Sample data only —
/// nothing here reads or writes the ledger.
extension Steven {

    enum GalleryPage: String, CaseIterable {
        case groups = "01", more = "05", myDetails = "07", expenses = "08"
        case standing = "09", payments = "10", amount = "12", details = "14"

        /// The page named by the `-StevenGallery` launch argument, if any.
        static var launchPage: GalleryPage? {
            UserDefaults.standard.string(forKey: "StevenGallery").flatMap(GalleryPage.init(rawValue:))
        }
    }

    struct Gallery: View {
        let page: GalleryPage

        var body: some View {
            switch page {
            case .groups: GalleryGroups()
            case .more: GalleryMore()
            case .myDetails: GalleryMyDetails()
            case .expenses: GalleryGroup(tab: 0)
            case .standing: GalleryGroup(tab: 1)
            case .payments: GalleryGroup(tab: 2)
            case .amount: GalleryAmount()
            case .details: GalleryDetails()
            }
        }
    }
}

private let members = StevenPreviewData.members
private let me = members[0].id

private struct GalleryGroups: View {
    @State private var tab = Steven.RootTab.groups

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: StevenMetric.cardGap) {
                    Steven.ScreenHeader(title: "Grupper", actionTitle: "Ny grupp", action: {})
                        .padding(.horizontal, -StevenMetric.gutter)
                    card("Vårt äktenskap", Array(members.prefix(2)), .theyOwe(amountMinor: 67_700, currency: .sek))
                    card("Hell dig", members, .settled)
                    card("Cph 17-19 April", Array(members.prefix(5)), .youOwe(amountMinor: 1_000, currency: .sek))
                }
                .padding(.horizontal, StevenMetric.gutter)
            }
            Steven.TabBar(selection: $tab, badges: [.notifications: 495])
        }
        .background(StevenColor.screen)
    }

    private func card(_ name: String, _ group: [Member], _ balance: Steven.Balance) -> some View {
        Steven.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: name).stevenFont(.cardTitle).foregroundStyle(StevenColor.ink)
                Steven.AvatarStack(members: group, me: me)
                HStack {
                    Text(verbatim: group.count == 2 ? "1 vän" : "\(group.count - 1) vänner")
                        .stevenFont(.rowTitle).foregroundStyle(StevenColor.muted)
                    Spacer()
                    Steven.BalanceLabel(state: balance, showsArchiveHint: true)
                }
            }
        }
    }
}

private struct GalleryMore: View {
    @State private var tab = Steven.RootTab.more
    @State private var reminders = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        Steven.AvatarView(member: members[0], size: StevenMetric.avatarHero)
                        Text(verbatim: "Carl Bedrot").stevenFont(.cardTitle).foregroundStyle(StevenColor.ink)
                        Text(verbatim: "070-123 45 67").stevenFont(.rowTitle).foregroundStyle(StevenColor.muted)
                    }
                    .padding(.vertical, 32)
                    Steven.Hairline(color: StevenColor.rowSeparator)
                    Steven.ListRow(title: "Mina detaljer") {
                        Steven.AvatarView(member: members[0], size: 28)
                    }
                    Steven.ListRow(icon: "circle.lefthalf.filled", title: "Utseende", trailing: .value("System"))
                    Steven.ListRow(icon: "bell", title: "Påminnelser", trailing: .toggle($reminders))
                    Steven.ListRow(icon: "questionmark.square", title: "Hjälpcenter")
                    Steven.ListRow(icon: "info.circle", title: "Om appen")
                    Steven.ListRow(icon: "square.and.arrow.up", title: "Dela till en vän")
                }
                .background(StevenColor.surface)
            }
            Steven.TabBar(selection: $tab, badges: [.notifications: 495])
        }
        .background(StevenColor.surface)
    }
}

private struct GalleryMyDetails: View {
    var body: some View {
        VStack(spacing: 0) {
            Steven.NavTitleBar(title: "Mina detaljer", leading: .back({}))
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    Steven.Card(padding: 0) {
                        VStack(spacing: 0) {
                            Steven.FormRow(label: "Profilbild") {
                                Steven.AvatarView(member: members[0], size: StevenMetric.avatarRow)
                            }
                            Steven.FormRow(label: "Namn", value: "Carl Bedrot")
                            Steven.FormRow(label: "Telefon", value: "070-123 45 67", showsSeparator: false)
                        }
                    }
                    Button("Logga ut") {}
                        .buttonStyle(Steven.OutlineButtonStyle())
                        .textCase(.uppercase)
                }
                .padding(StevenMetric.gutter)
            }
        }
        .background(StevenColor.screen)
    }
}

private struct GalleryGroup: View {
    @State var tab: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Steven.IconButton(systemName: "chevron.left", label: "Tillbaka", size: 28) {}
                Spacer()
                Steven.IconButton(systemName: "ellipsis", label: "Mer", weight: .bold, size: 20) {}
            }
            .padding(.horizontal, 6)
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(verbatim: "Vårt äktenskap").stevenFont(.groupTitle).foregroundStyle(StevenColor.ink)
                    Spacer()
                    Steven.MoneyText(amountMinor: 5_354_508, currency: .sek, font: .groupTitle)
                }
                HStack(spacing: 16) {
                    ForEach(members.prefix(2)) { member in
                        Steven.AvatarView(member: member, size: StevenMetric.avatarHeader)
                    }
                }
            }
            .padding(StevenMetric.gutter)
            Steven.UnderlineTabs(selection: $tab, tabs: [(0, "Utgifter"), (1, "Ställning"), (2, "Betalningar")])
            ScrollView { content }
                .background(StevenColor.content)
            Steven.BalanceFooter(balances: [.theyOwe(amountMinor: 67_655, currency: .sek)], onAdd: {})
        }
        .background(StevenColor.surface)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case 0:
            VStack(spacing: 0) {
                Steven.SectionHeader(verbatim: "Okt. 2026").padding(.top, 12)
                VStack(spacing: StevenMetric.cardGap + 8) {
                    expense("Køben", "måndag, 19 okt.", 36_800, mine: true, footer: "1 vän", payer: "Carl betalade")
                    expense("Middag puss", "torsdag, 8 okt.", 20_000, mine: false, footer: "Du och 1 vän", payer: "Anna betalade")
                }
                .padding(StevenMetric.gutter)
            }
        case 1:
            VStack(spacing: StevenMetric.cardGap) {
                standing(members[1], -67_655)
                standing(members[0], 67_655)
            }
            .padding(StevenMetric.gutter)
        default:
            Steven.InfoCard(title: "Så här beräknar vi betalningar", subtitle: "Läs mer här")
                .padding(StevenMetric.gutter)
        }
    }

    private func expense(_ title: String, _ date: String, _ minor: Int64, mine: Bool, footer: String, payer: String) -> some View {
        Steven.Card {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "doc.plaintext")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(StevenColor.ink)
                        .frame(width: StevenMetric.iconCircle, height: StevenMetric.iconCircle)
                        .background(mine ? StevenColor.accentTint : StevenColor.oweTint, in: .circle)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: title).stevenFont(.rowTitleBold).foregroundStyle(StevenColor.ink)
                        Text(verbatim: date).stevenFont(.footnote).foregroundStyle(StevenColor.ink)
                    }
                    Spacer()
                    Steven.MoneyText(amountMinor: minor, currency: .sek)
                }
                HStack {
                    Text(verbatim: footer)
                    Spacer()
                    Text(verbatim: payer)
                }
                .stevenFont(.footnoteBold)
                .foregroundStyle(StevenColor.faint)
            }
        }
    }

    private func standing(_ member: Member, _ net: Int64) -> some View {
        Steven.Card {
            HStack(spacing: 16) {
                Steven.AvatarView(member: member)
                Text(verbatim: member.displayName).stevenFont(.rowTitleBold).foregroundStyle(StevenColor.ink)
                Spacer()
                Steven.MoneyText(amountMinor: net, currency: .sek, tone: .direction, sign: .negativeOnly)
                Rectangle().fill(StevenColor.hairline).frame(width: 1, height: 32)
                Image(systemName: "chevron.down").font(.system(size: 17, weight: .light))
                    .foregroundStyle(StevenColor.ink)
            }
        }
    }
}

private struct GalleryAmount: View {
    @State private var digits = ""

    var body: some View {
        VStack(spacing: 0) {
            Steven.NavTitleBar(leading: .close({})) {
                HStack(spacing: 6) {
                    Text("Utgift")
                    Image(systemName: "chevron.down").font(.system(size: 15, weight: .light))
                }
            }
            HStack {
                Button {} label: {
                    HStack(spacing: 12) {
                        Steven.AvatarView(member: members[0], size: 24)
                        Text(verbatim: "Carl betalade").stevenFont(.rowTitle)
                        Steven.Chevron()
                    }
                    .foregroundStyle(StevenColor.ink)
                    .padding(.horizontal, 10)
                    .frame(minHeight: StevenMetric.minimumHitTarget)
                    .overlay {
                        RoundedRectangle(cornerRadius: StevenMetric.controlRadius)
                            .strokeBorder(StevenColor.hairline, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(StevenMetric.gutter + 4)
            Spacer()
            HStack(alignment: .center, spacing: 10) {
                Text(verbatim: digits.isEmpty ? "0" : digits)
                    .stevenFont(.amountHero)
                    .foregroundStyle(digits.isEmpty ? StevenColor.placeholder : StevenColor.ink)
                Text(verbatim: "SEK ›")
                    .stevenFont(.rowTitle)
                    .foregroundStyle(StevenColor.ink)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .overlay {
                        RoundedRectangle(cornerRadius: StevenMetric.controlRadius)
                            .strokeBorder(StevenColor.hairline, lineWidth: 1)
                    }
            }
            Spacer()
            HStack {
                Image(systemName: "plus.forwardslash.minus").font(.system(size: 24, weight: .light))
                    .foregroundStyle(StevenColor.muted)
                Spacer()
                Button("Nästa") {}
                    .buttonStyle(Steven.FilledButtonStyle(height: 38))
                    .frame(width: 72)
                    .disabled(digits.isEmpty)
            }
            .padding(.horizontal, StevenMetric.gutter)
            .padding(.bottom, 8)
            Steven.Keypad { key in
                switch key {
                case .digit(let digit): digits.append(String(digit))
                case .decimal: if !digits.contains(",") { digits.append(",") }
                case .delete: if !digits.isEmpty { digits.removeLast() }
                }
            }
        }
        .background(StevenColor.surface, ignoresSafeAreaEdges: .top)
        .background(StevenColor.keyboardBase.ignoresSafeArea())
    }
}

private struct GalleryDetails: View {
    @State private var category: String? = "taxi"
    @State private var carl = true
    @State private var anna = true

    var body: some View {
        VStack(spacing: 0) {
            Steven.NavTitleBar(title: "Utgift", leading: .back({}))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "Taxi").stevenFont(.rowTitle).foregroundStyle(StevenColor.ink)
                        .padding(.horizontal, StevenMetric.gutter + 12).padding(.vertical, 28)
                    Steven.ChipRow(
                        chips: [.init(id: "taxi", title: "Taxi"), .init(id: "shop", title: "Shopping"),
                                .init(id: "bar", title: "Bar"), .init(id: "trip", title: "Resa")],
                        selection: $category,
                        onMore: {}
                    )
                    Steven.SectionHeader("Deltagare").padding(.top, 8)
                    participant(members[0], $carl)
                    participant(members[1], $anna)
                    Button {} label: {
                        Text("Återställ till att dela lika").stevenFont(.rowTitleBold).foregroundStyle(StevenColor.accent)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, StevenMetric.gutter + 4).padding(.vertical, 20)
                    Steven.SectionHeader("Annan")
                    Steven.ListRow(title: "Datum", trailing: .value("Idag")) { EmptyView() }
                }
            }
            Button("Spara") {}
                .buttonStyle(Steven.FilledButtonStyle())
                .padding(StevenMetric.gutter + 4)
        }
        .background(StevenColor.surface)
    }

    private func participant(_ member: Member, _ ticked: Binding<Bool>) -> some View {
        HStack(spacing: 16) {
            Steven.AvatarView(member: member)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: member.displayName).stevenFont(.rowTitle).foregroundStyle(StevenColor.ink)
                Steven.MoneyText(amountMinor: 5_000, currency: .sek, font: .footnote, tone: .muted)
            }
            Spacer()
            Text(verbatim: "50 %")
                .stevenFont(.rowTitle)
                .foregroundStyle(StevenColor.muted)
                .frame(width: 130, height: 40)
                .overlay {
                    RoundedRectangle(cornerRadius: StevenMetric.controlRadius)
                        .strokeBorder(StevenColor.hairline, lineWidth: 1)
                }
            Steven.CheckBox(isOn: ticked)
        }
        .padding(.leading, StevenMetric.gutter + 4)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
    }
}

#Preview("Gallery 08 – light") { Steven.Gallery(page: .expenses) }
#Preview("Gallery 08 – dark") { Steven.Gallery(page: .expenses).preferredColorScheme(.dark) }
#endif
