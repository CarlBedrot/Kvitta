import SwiftUI
import UIKit
import KvittaCore

/// Ny utgift — the amount-first add sheet. Opens straight onto a big amount over a custom keypad,
/// Swish-style: the 90 % case is amount + description, then Spara, in under ten seconds.
///
/// Glass budget: the group menu (1) and Spara (1). The suggestion chips are drawn opaque, not
/// glass — the mockup shows them glass, but menu + Spara + three chips would be five glass
/// elements and the restraint rule caps a screen at three.
struct NewExpenseSheet: View {
    @Bindable var model: NewExpenseModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingSplitEditor = false
    @State private var saveTick = 0

    /// Only groups you can actually split in appear in the menu.
    private var selectableGroups: [GroupState] {
        model.ledger.state.groupsByLastActivity.filter { $0.activeMembers.count >= 2 }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(model: model, groups: selectableGroups, onCancel: { dismiss() })
            AmountDisplay(
                display: model.amount.display,
                currency: model.currency,
                primary: model.group?.currency ?? .sek,
                // Locked while editing: correcting an amount is not re-denominating the dinner.
                onCurrency: model.isEditing ? nil : { model.currency = $0 }
            )
            DescriptionSection(model: model)
            SummaryRow(model: model) { showingSplitEditor = true }
            Spacer(minLength: 8)
            Keypad(amount: $model.amount)
            SaveButton(enabled: model.isValid, action: save)
        }
        .background(AmbientBackground())
        .sheet(isPresented: $showingSplitEditor) {
            SplitEditorSheet(model: model)
        }
        .sensoryFeedback(.success, trigger: saveTick)
        .alert("Kunde inte spara", isPresented: failureBinding) {
            Button("OK", role: .cancel) { model.failure = nil }
        } message: {
            Text(model.failure ?? "")
        }
    }

    private var failureBinding: Binding<Bool> {
        Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })
    }

    private func save() {
        // Local and instant — a haptic and dismissal, never a spinner (CLAUDE.md).
        if model.save() {
            saveTick += 1
            dismiss()
        }
    }
}

// MARK: - Header

private struct SheetHeader: View {
    @Bindable var model: NewExpenseModel
    let groups: [GroupState]
    let onCancel: () -> Void

    var body: some View {
        HStack {
            if model.isEditing {
                // An edit stays in its group: moving an expense between ledgers is not a
                // correction, it is a delete and a re-add.
                Text(model.group?.name ?? "")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
            } else {
                Menu {
                    ForEach(groups) { group in
                        Button(group.name) { model.selectGroup(group.id) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(model.group?.name ?? "")
                        Image(systemName: "chevron.down").font(.caption)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(Theme.card, in: .capsule)
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                }
            }

            Spacer()

            Button("Avbryt", action: onCancel)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

// MARK: - Amount

private struct AmountDisplay: View {
    let display: String
    let currency: CurrencyCode
    let primary: CurrencyCode
    /// `nil` locks the currency (editing). Otherwise the suffix is a menu — the M7 entry point:
    /// type 200, tap "kr", pick DKK, and the dinner lands in the DKK bucket.
    let onCurrency: ((CurrencyCode) -> Void)?

    private static let choices: [CurrencyCode] = [.sek, .dkk, .nok, .eur]

    /// Explicit whenever the expense strays from the group's primary — "kr" alone cannot say
    /// which kronor.
    private var suffix: String {
        currency == primary ? MoneyFormat.symbol(currency) : currency.code
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(display)
                .font(.system(size: 58, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            if let onCurrency {
                Menu {
                    ForEach(Self.choices, id: \.self) { choice in
                        Button(choice == primary ? "\(choice.code) · \(MoneyFormat.symbol(choice))" : choice.code) {
                            onCurrency(choice)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(suffix)
                            .font(.system(size: 26, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(currency == primary ? Theme.secondary : Theme.accent)
                }
            } else {
                Text(suffix)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 6)
        .contentTransition(.numericText())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Belopp \(display) \(currency.code)")
    }
}

// MARK: - Description + chips

private struct DescriptionSection: View {
    @Bindable var model: NewExpenseModel

    /// This group's chips; the starters alone while the group is still loading.
    private var suggestions: [DescriptionSuggestion] {
        model.group.map(DescriptionSuggestion.suggestions(for:)) ?? DescriptionSuggestion.starters
    }

    var body: some View {
        VStack(spacing: 12) {
            TextField("Beskrivning…", text: $model.descriptionText)
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .background(Theme.card, in: .rect(cornerRadius: 18))
                .shadow(color: .black.opacity(0.04), radius: 5, y: 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            model.descriptionText = suggestion.text
                            model.categoryId = suggestion.categoryId
                        } label: {
                            Text(verbatim: "\(suggestion.emoji) \(suggestion.text)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Theme.card, in: .rect(cornerRadius: 18))
                                .shadow(color: .black.opacity(0.04), radius: 5, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, -20)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }
}

// MARK: - Summary row

/// The sentence ("Du betalade · delas lika (4)") and, under it, the split itself: the faces it
/// lands on and what each carries. The sentence said *how*; this row shows *who* and *how much*,
/// which is the reassurance people used to open the editor for. Still one tap target — the
/// whole card opens `SplitEditorSheet`.
private struct SummaryRow: View {
    let model: NewExpenseModel
    let action: () -> Void

    @Environment(\.myAvatarPhoto) private var myAvatarPhoto

    var body: some View {
        let preview = model.draft.preview(totalMinor: model.amountMinor, members: model.memberIds)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    summaryText(count: preview.participants.count).foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
                }
                .font(.subheadline.weight(.medium))
                if !preview.participants.isEmpty {
                    HStack(spacing: 10) {
                        ParticipantFaces(members: preview.participants.compactMap(member(for:)),
                                         meId: model.meId, myPhoto: myAvatarPhoto,
                                         name: model.name(for:))
                        Text(perPerson(preview))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .shadow(color: .black.opacity(0.04), radius: 5, y: 2)
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
        .accessibilityValue(spoken(preview))
    }

    private func summaryText(count: Int) -> Text {
        let payer: Text = model.isPayerMe
            ? Text("Du betalade")
            : Text("\(model.payerMember.map(model.name(for:)) ?? "") betalade")
        return payer + Text(verbatim: " · ") + Text(model.draft.mode.sentenceLabel) + Text(verbatim: " (\(count))")
    }

    private func member(for id: MemberID) -> Member? {
        model.members.first { $0.id == id }
    }

    /// "120 kr var" when everyone carries the same; the actual amounts when they don't and
    /// there are few enough to read; otherwise just how many differ. Nothing until an amount
    /// exists — the faces alone say who is in.
    private func perPerson(_ preview: SplitDraft.Preview) -> String {
        if let each = preview.perPersonMinor {
            return String(localized: "\(MoneyFormat.string(each, model.currency)) var")
        }
        guard !preview.shares.isEmpty else { return "" }
        if preview.shares.count <= 3 {
            return preview.shares
                .map { MoneyFormat.string($0.amountMinor, model.currency) }
                .joined(separator: " · ")
        }
        return String(localized: "\(preview.shares.count) olika andelar")
    }

    private func spoken(_ preview: SplitDraft.Preview) -> String {
        let names = preview.participants.compactMap(member(for:)).map(model.name(for:))
        return ([names.joined(separator: ", ")] + [perPerson(preview)]).filter { !$0.isEmpty }
            .joined(separator: ". ")
    }
}

/// The participants as one overlapping run of faces — a group sharing a cost is one object,
/// like the pair in a transfer. You wear your photo; everyone else their initials. Past five the
/// run ends in a count, because a dinner for twelve is not twelve legible circles.
private struct ParticipantFaces: View {
    let members: [Member]
    let meId: MemberID?
    let myPhoto: Data?
    let name: (Member) -> String

    private let size: CGFloat = 28
    private let shown = 5

    var body: some View {
        let visible = members.prefix(shown)
        let overflow = members.count - visible.count
        HStack(spacing: -8) {
            ForEach(Array(visible), id: \.id) { member in
                Avatar(name: name(member), photo: member.id == meId ? myPhoto : nil, size: size)
                    .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
            }
            if overflow > 0 {
                Text(verbatim: "+\(overflow)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: size, height: size)
                    .background(Theme.bg, in: .circle)
                    .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Keypad

private struct Keypad: View {
    @Binding var amount: AmountInput

    private let rows: [[KeypadKey]] = [
        [.digit("1"), .digit("2"), .digit("3")],
        [.digit("4"), .digit("5"), .digit("6")],
        [.digit("7"), .digit("8"), .digit("9")],
        [.comma, .digit("0"), .backspace],
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(rows[row]) { key in
                        KeyButton(key: key) { press(key) }
                    }
                }
            }
        }
        .padding(.horizontal, 34)
        .padding(.top, 8)
        // A key that moves nothing — backspace on an empty amount, a second comma — is a key that
        // did nothing, and the silence is the honest answer. Triggering on the value rather than
        // on the tap gets that for free.
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.45), trigger: amount)
    }

    private func press(_ key: KeypadKey) {
        switch key {
        case .digit(let d): amount.input(d)
        case .comma: amount.comma()
        case .backspace: amount.backspace()
        }
    }
}

private enum KeypadKey: Identifiable, Hashable {
    case digit(Character)
    case comma
    case backspace

    var id: String {
        switch self {
        case .digit(let d): return String(d)
        case .comma: return ","
        case .backspace: return "⌫"
        }
    }

    var label: String {
        switch self {
        case .digit(let d): return String(d)
        case .comma: return ","
        case .backspace: return "⌫"
        }
    }
}

private struct KeyButton: View {
    let key: KeypadKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(key.label)
                .font(.system(size: 27, weight: .regular))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch key {
        case .digit(let d): return String(d)
        case .comma: return String(localized: "komma")
        case .backspace: return String(localized: "radera")
        }
    }
}

// MARK: - Save

private struct SaveButton: View {
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button("Spara", action: action)
            .buttonStyle(PrimaryButtonStyle())
            .opacity(enabled ? 1 : 0.5)
        .disabled(!enabled)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 30)
    }
}
