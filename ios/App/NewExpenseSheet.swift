import SwiftUI
import UIKit
import KvittaCore

/// Ny utgift — the amount-first add sheet, in Steven's two steps (README §3.1): belopp
/// (`ExpenseAmountStep`, 12/13), then description, category, split and date here. An edit has
/// nothing new to type into the amount, so it opens straight on this step (§3.2); "Tillbaka"
/// still reaches the amount step either way.
struct NewExpenseSheet: View {
    @Bindable var model: NewExpenseModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingSplitEditor = false
    @State private var saveTick = 0
    @State private var step: Step

    private enum Step { case amount, details }

    init(model: NewExpenseModel) {
        self.model = model
        _step = State(initialValue: model.isEditing ? .details : .amount)
    }

    var body: some View {
        switch step {
        case .amount:
            ExpenseAmountStep(model: model, onCancel: { dismiss() }, onNext: { step = .details })
        case .details:
            detailsStep
        }
    }

    private var detailsStep: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    DetailsHeader(onBack: { step = .amount }, onCancel: { dismiss() })
                    DescriptionSection(model: model)
                    SummaryRow(model: model) { showingSplitEditor = true }
                    Spacer(minLength: 8)
                    SaveButton(enabled: model.isValid, action: save)
                }
                .frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        // The same wash as the group's own screen.
        .background(Theme.bg)
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

// MARK: - Details header

private struct DetailsHeader: View {
    let onBack: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel(Text("Tillbaka"))
            Spacer()
            Button("Avbryt", action: onCancel)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.secondary)
                .fixedSize()
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

// MARK: - Description

private struct DescriptionSection: View {
    @Bindable var model: NewExpenseModel

    var body: some View {
        TextField("Beskrivning…", text: $model.descriptionText)
            .sliceField()
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
                    summaryText(count: preview.participants.count)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.tertiary)
                }
                .font(.subheadline.weight(.medium))
                if !preview.participants.isEmpty {
                    HStack(spacing: 10) {
                        MemberFaces(members: preview.participants.compactMap(member(for:)),
                                         meId: model.meId, myPhoto: myAvatarPhoto,
                                         name: model.name(for:))
                        Text(perPerson(preview))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                            .monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(Theme.card, in: .rect(cornerRadius: 18))
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
