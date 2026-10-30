import SwiftUI
import KvittaCore

/// Steven's second "Ny utgift" step (README §3.1, image 14): description, category, DELTAGARE
/// and ANNAN, then Spara.
///
/// **Unwired for now.** Steven 8 (#152, still open as PR #165) is what gives `NewExpenseSheet`
/// its own two-step flow (amount → details); until that PR merges, `main` has no "step 2" to
/// mount this into. This view is ready for whoever lands #152 to present as the details step —
/// the same stand-alone-first pattern #167 used for `GroupStandingTab`.
struct ExpenseDetailsStep: View {
    @Bindable var model: NewExpenseModel
    let onBack: () -> Void
    let onSave: () -> Void

    /// `nil` until the user taps a chip — until then the chip row follows `Categories.infer`
    /// live, exactly like `NewExpenseModel.resolvedPayload()` does at save time (CLAUDE.md:
    /// "manuellt val vinner").
    @State private var manualCategory: String?
    @State private var showingAllCategories = false
    @State private var showingDatePicker = false
    @State private var percentText: [MemberID: String] = [:]
    @State private var exactText: [MemberID: String] = [:]
    @State private var saveTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: NewExpenseModel, onBack: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.model = model
        self.onBack = onBack
        self.onSave = onSave
        _manualCategory = State(initialValue: model.categoryId == Categories.fallbackId ? nil : model.categoryId)
        // Andelar is retired from this screen (#153): an expense created in that mode reopens
        // as plain exact kr, carrying the same resolved shares it already had.
        if model.draft.mode == .shares {
            let resolved = model.draft.resolvedShares(totalMinor: model.amountMinor, members: model.memberIds) ?? []
            model.draft.mode = .exact
            for line in resolved { model.draft.exactMinor[line.memberId] = line.amountMinor }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Steven.NavTitleBar(title: "Utgift", leading: .back(onBack))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    descriptionField
                    categoryChips
                    Steven.SectionHeader("Deltagare").padding(.top, 8)
                    ForEach(model.members) { member in
                        participantRow(member)
                    }
                    resetButton
                    Steven.SectionHeader("Annan")
                    dateSection
                }
            }
            .scrollDismissesKeyboard(.interactively)
            Button("Spara", action: save)
                .buttonStyle(Steven.FilledButtonStyle())
                .disabled(!model.isValid)
                .padding(StevenMetric.gutter + 4)
        }
        .background(StevenColor.surface)
        .sensoryFeedback(.success, trigger: saveTick)
        .alert("Kunde inte spara", isPresented: failureBinding) {
            Button("OK", role: .cancel) { model.failure = nil }
        } message: {
            Text(model.failure ?? "")
        }
        .sheet(isPresented: $showingAllCategories) {
            CategoryPickerSheet(selection: categoryBinding)
        }
    }

    private var failureBinding: Binding<Bool> {
        Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } })
    }

    private func save() {
        // Local and instant — a haptic and dismissal, never a spinner (CLAUDE.md).
        if model.save() {
            saveTick += 1
            onSave()
        }
    }

    // MARK: - Description & category

    private var selectedCategoryId: String {
        manualCategory ?? Categories.infer(from: model.descriptionText)
    }

    private var categoryBinding: Binding<String?> {
        Binding(
            get: { selectedCategoryId },
            set: { newValue in
                manualCategory = newValue
                if let newValue { model.categoryId = newValue }
            }
        )
    }

    private var descriptionField: some View {
        let placeholder = Categories.all.first { $0.id == selectedCategoryId }?.name ?? ""
        return TextField(placeholder, text: $model.descriptionText)
            .stevenFont(.rowTitle)
            .foregroundStyle(StevenColor.ink)
            .padding(.horizontal, StevenMetric.gutter + 12)
            .padding(.vertical, 28)
    }

    private var categoryChips: some View {
        let recent = Categories.recentlyUsed(in: model.group)
        return Steven.ChipRow(
            chips: recent.map { Steven.Chip(id: $0.id, title: $0.name) },
            selection: categoryBinding,
            onMore: { showingAllCategories = true }
        )
    }

    // MARK: - Participants

    private var shareMap: [MemberID: Int64] {
        let shares = model.draft.resolvedShares(totalMinor: model.amountMinor, members: model.memberIds) ?? []
        return Dictionary(uniqueKeysWithValues: shares.map { ($0.memberId, $0.amountMinor) })
    }

    private func participantRow(_ member: Member) -> some View {
        HStack(spacing: 16) {
            Steven.AvatarView(member: member, isMe: model.meId == member.id)
            Button(action: switchToExactMode) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: model.name(for: member)).stevenFont(.rowTitle).foregroundStyle(StevenColor.ink)
                    Steven.MoneyText(amountMinor: shareMap[member.id] ?? 0, currency: model.currency,
                                     font: .footnote, tone: .muted)
                }
                .frame(minHeight: StevenMetric.minimumHitTarget, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(model.draft.mode == .exact)
            .accessibilityLabel(Text("Växla till exakt belopp"))
            Spacer()
            fieldBox(member)
            Steven.CheckBox(isOn: includedBinding(member.id), accessibilityLabel: Text(verbatim: model.name(for: member)))
        }
        .padding(.leading, StevenMetric.gutter + 4)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
    }

    // The field's unit switches between "%" and "kr" with the draft's mode — never AnyView
    // (CLAUDE.md), just a switch returning concrete views.
    @ViewBuilder
    private func fieldBox(_ member: Member) -> some View {
        if model.draft.mode == .exact {
            field(text: exactBinding(member.id), placeholder: exactPlaceholder(member.id), unit: MoneyFormat.symbol(model.currency))
        } else {
            field(text: percentBinding(member.id), placeholder: percentPlaceholder(member.id), unit: "%")
        }
    }

    private func field(text: Binding<String>, placeholder: String, unit: String) -> some View {
        HStack(spacing: 4) {
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
            Text(verbatim: unit).foregroundStyle(StevenColor.muted)
        }
        .stevenFont(.rowTitle)
        .foregroundStyle(StevenColor.ink)
        .padding(.horizontal, 10)
        .frame(width: 104, height: StevenMetric.compactButtonHeight)
        .overlay {
            RoundedRectangle(cornerRadius: StevenMetric.controlRadius)
                .strokeBorder(StevenColor.hairline, lineWidth: 1)
        }
    }

    /// Nothing is typed yet in equal mode, so the field shows the live equal share as a
    /// placeholder rather than writing it into the draft.
    private func percentPlaceholder(_ id: MemberID) -> String {
        guard model.amountMinor > 0, let shareMinor = shareMap[id] else { return "0" }
        let bp = (shareMinor * SplitInput.percentageTotalBasisPoints) / model.amountMinor
        return SplitParse.text(fromMinor: bp)
    }

    private func percentBinding(_ id: MemberID) -> Binding<String> {
        Binding(
            get: { percentText[id] ?? "" },
            set: { newValue in
                if model.draft.mode != .percentage { seedPercentageFromCurrentSplit() }
                percentText[id] = newValue
                model.draft.basisPoints[id] = SplitParse.minor(newValue)
            }
        )
    }

    private func exactPlaceholder(_ id: MemberID) -> String {
        SplitParse.text(fromMinor: shareMap[id] ?? 0)
    }

    private func exactBinding(_ id: MemberID) -> Binding<String> {
        Binding(
            get: { exactText[id] ?? "" },
            set: { newValue in
                exactText[id] = newValue
                model.draft.exactMinor[id] = SplitParse.minor(newValue)
            }
        )
    }

    /// "Tryck på kr-beloppet växlar fältet till exakt kr" (#153): seeds every row's exact amount
    /// from whatever is currently resolved, so the switch never jumps the numbers on screen.
    private func switchToExactMode() {
        guard model.draft.mode != .exact else { return }
        let resolved = model.draft.resolvedShares(totalMinor: model.amountMinor, members: model.memberIds) ?? []
        model.draft.mode = .exact
        model.draft.exactMinor = Dictionary(uniqueKeysWithValues: model.memberIds.map { ($0, 0) })
        for line in resolved { model.draft.exactMinor[line.memberId] = line.amountMinor }
        exactText = model.draft.exactMinor.compactMapValues { $0 == 0 ? nil : SplitParse.text(fromMinor: $0) }
        percentText = [:]
    }

    /// The first edit to any percent field moves the draft out of Lika — seeded from the equal
    /// split so the other rows do not suddenly read 0 %, with Core's own remainder-to-the-lowest-
    /// memberId convention fixing the rounding so the total lands on exactly 10 000 bp.
    private func seedPercentageFromCurrentSplit() {
        let resolved = model.draft.resolvedShares(totalMinor: model.amountMinor, members: model.memberIds) ?? []
        model.draft.mode = .percentage
        model.draft.basisPoints = Dictionary(uniqueKeysWithValues: model.memberIds.map { ($0, 0) })
        guard model.amountMinor > 0 else { return }
        for line in resolved {
            model.draft.basisPoints[line.memberId] = (line.amountMinor * SplitInput.percentageTotalBasisPoints) / model.amountMinor
        }
        let remainder = SplitInput.percentageTotalBasisPoints - model.draft.basisPointsSum(members: model.memberIds)
        if remainder != 0, let lowest = model.memberIds.sorted().first {
            model.draft.basisPoints[lowest, default: 0] += remainder
        }
        percentText = model.draft.basisPoints.compactMapValues { $0 == 0 ? nil : SplitParse.text(fromMinor: $0) }
    }

    // MARK: - Checkbox / inclusion

    private func includedBinding(_ id: MemberID) -> Binding<Bool> {
        Binding(get: { currentlyIncludedIds().contains(id) }, set: { _ in toggleIncluded(id) })
    }

    private func currentlyIncludedIds() -> Set<MemberID> {
        switch model.draft.mode {
        case .equal: model.draft.included
        case .exact: Set(model.memberIds.filter { (model.draft.exactMinor[$0] ?? 0) != 0 })
        case .percentage: Set(model.memberIds.filter { (model.draft.basisPoints[$0] ?? 0) != 0 })
        case .shares: Set(model.memberIds)
        }
    }

    /// Unchecking or re-checking anyone always lands on a fresh, correctly-rounded equal split
    /// of whoever is left — "Avbockning → lika bland resterande" (#153) generalised to every
    /// mode, through the same `SplitCalculator` the save path uses, so a checkbox can never
    /// leave the draft unbalanced.
    private func toggleIncluded(_ id: MemberID) {
        if model.draft.mode == .equal {
            if model.draft.included.contains(id) {
                model.draft.included.remove(id)
            } else {
                model.draft.included.insert(id)
            }
            return
        }
        var ids = currentlyIncludedIds()
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        guard !ids.isEmpty else {
            resetToEqualSplit()
            return
        }
        guard let resolved = try? SplitCalculator.resolve(totalMinor: model.amountMinor, input: .equal(among: Array(ids))) else {
            return
        }
        model.draft.exactMinor = Dictionary(uniqueKeysWithValues: model.memberIds.map { ($0, 0) })
        for line in resolved { model.draft.exactMinor[line.memberId] = line.amountMinor }
        model.draft.mode = .exact
        exactText = model.draft.exactMinor.compactMapValues { $0 == 0 ? nil : SplitParse.text(fromMinor: $0) }
        percentText = [:]
    }

    private var resetButton: some View {
        Button(action: resetToEqualSplit) {
            Text("Återställ till att dela lika").stevenFont(.rowTitleBold).foregroundStyle(StevenColor.accent)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, StevenMetric.gutter + 4)
        .padding(.vertical, 20)
    }

    private func resetToEqualSplit() {
        model.draft.mode = .equal
        model.draft.included = Set(model.memberIds)
        percentText = [:]
        exactText = [:]
    }

    // MARK: - Date

    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.year = model.date.year
                components.month = model.date.month
                components.day = model.date.day
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { model.date = CalendarDate($0) }
        )
    }

    private var dateValueText: String {
        model.date == CalendarDate(Date()) ? String(localized: "Idag") : model.date.displayString
    }

    private var dateSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { showingDatePicker.toggle() }
            } label: {
                Steven.ListRow(title: "Datum", trailing: .value(dateValueText), showsSeparator: !showingDatePicker) { EmptyView() }
            }
            .buttonStyle(Steven.RowButtonStyle())
            // No Upprepa (#153): this expense happened once, on one day.
            if showingDatePicker {
                DatePicker("", selection: dateBinding, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(StevenColor.accent)
                    .padding(.horizontal, StevenMetric.gutter)
            }
        }
    }
}

/// The "…" sheet (#153): every category, not just the chip row's recent ones.
private struct CategoryPickerSheet: View {
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(Categories.all) { category in
                Button {
                    selection = category.id
                    dismiss()
                } label: {
                    HStack {
                        Text(verbatim: "\(category.emoji)  \(category.name)")
                        Spacer()
                        if category.id == selection {
                            Image(systemName: "checkmark").foregroundStyle(StevenColor.accent)
                        }
                    }
                }
                .foregroundStyle(StevenColor.ink)
            }
            .navigationTitle(Text("Alla kategorier"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stäng") { dismiss() }
                }
            }
        }
    }
}
