import SwiftUI
import KvittaCore
import KvittaStorage

/// Creating a group: a name, a currency, and you. Steven-styled per README §3.4 — there is no
/// reference screenshot for this sheet, so the layout is a guess built from the same components
/// and typography as 11 (gruppinställningar) and 14 (ny utgift, steg 2).
///
/// It used to ask you to type everybody's names up front, which is the wrong shape twice over —
/// it is work before you have got anything, and the names you invent are then the names your
/// friends are stuck with when they join. Now the group starts with you and fills up from the
/// invite link, and creating it hands you straight into the group so the link is the next thing
/// you see.
///
/// Adding someone by name did not go away, it moved: `MembersSheet` still does it, for the person
/// who will never install the app. That is design doc §5's "single most important UX decision" and
/// it is not up for removal — it is just no longer the price of making a group.
struct NewGroupSheet: View {
    let ledger: LedgerStore
    let userId: UserID
    let profile: UserProfile
    var onCreated: (GroupID) -> Void = { _ in }
    /// The other way into a group: somebody sent you a link. Closes this sheet and opens Gå med.
    var onJoinInstead: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var currency: CurrencyCode = .sek
    @State private var failure: String?

    private static let currencies: [CurrencyCode] = [.sek, .dkk, .nok, .eur]

    /// The icon lives *in the name* — "🏔️ Fjällresan" — because that is what `GroupBadge` already
    /// reads, and a name syncs to every phone for free where a separate field would need an
    /// event of its own. The row is just a faster way to type the first character.
    private static let emojiSuggestions: [Character] = ["✈️", "🏠", "🍕", "🎾", "⛰️", "🎉", "🚗", "🛒", "💑", "🎓"]

    /// Whatever emoji the name currently opens with — typed or tapped, the badge treats them alike.
    private var chosenEmoji: Character? { GroupBadge.emoji(of: name) }

    /// Tap to set, tap again to clear; either way the rest of the name is left alone. `ChipRow`
    /// always reports the tapped chip, never a toggle, so the clear-on-second-tap behaviour lives
    /// here rather than in the shared component.
    private func choose(_ emoji: Character) {
        let title = GroupBadge.title(of: name)
        name = chosenEmoji == emoji ? title : "\(emoji) \(title)"
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func currencyLabel(_ code: CurrencyCode) -> String {
        MoneyFormat.symbol(code) == code.code ? code.code : "\(code.code) · \(MoneyFormat.symbol(code))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Steven.NavTitleBar(title: "Ny grupp", leading: .close({ dismiss() }))
            ScrollView {
                VStack(spacing: StevenMetric.cardGap) {
                    Steven.Card(padding: 0) {
                        TextField("Namn (t.ex. 🏔️ Fjällresan)", text: $name)
                            .stevenFont(.rowTitle)
                            .foregroundStyle(StevenColor.ink)
                            .padding(.horizontal, StevenMetric.gutter)
                            .frame(minHeight: StevenMetric.rowHeight)
                            .accessibilityLabel(Text("Gruppnamn"))
                    }

                    emojiRow
                        .padding(.horizontal, -StevenMetric.gutter)

                    currencyRow

                    if let failure {
                        errorNotice(failure)
                    }

                    Button("Har du fått en länk? Gå med") {
                        dismiss()
                        onJoinInstead()
                    }
                    .buttonStyle(.plain)
                    .stevenFont(.rowTitle)
                    .foregroundStyle(StevenColor.accent)
                    .frame(minHeight: StevenMetric.minimumHitTarget)
                }
                .padding(StevenMetric.gutter)
            }
            Button("Skapa", action: create)
                .buttonStyle(Steven.FilledButtonStyle())
                .disabled(!canCreate)
                .padding(.horizontal, StevenMetric.gutter)
                .padding(.vertical, 12)
        }
        .background(StevenColor.screen)
    }

    private var emojiRow: some View {
        Steven.ChipRow(
            chips: Self.emojiSuggestions.map { Steven.Chip(id: $0, title: String($0)) },
            selection: Binding(
                get: { chosenEmoji },
                set: { newValue in if let newValue { choose(newValue) } }
            ),
            onMore: nil
        )
    }

    private var currencyRow: some View {
        Steven.Card(padding: 0) {
            Menu {
                ForEach(Self.currencies, id: \.self) { code in
                    Button(currencyLabel(code)) { currency = code }
                }
            } label: {
                Steven.FormRow(label: "Valuta", showsSeparator: false) {
                    HStack(spacing: 8) {
                        Text(verbatim: currencyLabel(currency))
                            .stevenFont(.rowTitle)
                            .foregroundStyle(StevenColor.inkSoft)
                        Steven.Chevron()
                    }
                }
            }
        }
    }

    private func errorNotice(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(StevenColor.badge)
            Text(verbatim: text)
                .stevenFont(.footnote)
                .foregroundStyle(StevenColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StevenMetric.cardPadding)
        .stevenCardBackground()
        .accessibilityElement(children: .combine)
    }

    private func create() {
        do {
            let groupId = GroupID()
            try ledger.record(
                .groupCreated(GroupCreatedPayload(name: name.trimmingCharacters(in: .whitespaces), currency: currency)),
                entityId: groupId.rawValue, in: groupId
            )
            // The Mer tab promises your name "visas som du i nya grupper". This is where that
            // promise is kept; before, the sheet had its own field defaulting to "Du" and the
            // profile name was never read.
            try ledger.record(
                .memberAdded(MemberAddedPayload(
                    displayName: profile.nameOrDefault,
                    linkedUserId: userId
                )),
                entityId: MemberID().rawValue, in: groupId
            )
            onCreated(groupId)
            dismiss()
        } catch {
            // A local write failing must surface, never vanish (CLAUDE.md).
            failure = String(describing: error)
        }
    }
}
