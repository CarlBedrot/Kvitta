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

    var body: some View {
        VStack(spacing: 12) {
            TextField("Beskrivning…", text: $model.descriptionText)
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .background(Theme.card, in: .rect(cornerRadius: 18))
                .shadow(color: .black.opacity(0.04), radius: 5, y: 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DescriptionSuggestion.starters) { suggestion in
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

private struct SummaryRow: View {
    let model: NewExpenseModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                summaryText.foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .shadow(color: .black.opacity(0.04), radius: 5, y: 2)
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var summaryText: Text {
        let count = model.draft.participantCount(totalMinor: model.amountMinor, members: model.memberIds)
        let payer: Text = model.isPayerMe
            ? Text("Du betalade")
            : Text("\(model.payerMember.map(model.name(for:)) ?? "") betalade")
        return payer + Text(verbatim: " · ") + Text(model.draft.mode.sentenceLabel) + Text(verbatim: " (\(count))")
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
