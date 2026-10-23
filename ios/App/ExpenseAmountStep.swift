import SwiftUI
import KvittaCore

/// Ny utgift steg 1 (12, 13; README §1.2, §3.1): a big amount over Steven's keypad, Swish-style —
/// amount, payer and currency, then `Nästa`. Step 2 (description, category, split, date) still
/// lives in `NewExpenseSheet` itself until Steven 9 (#153) rebuilds it to match 14; this view
/// only ever owns the amount.
struct ExpenseAmountStep: View {
    @Bindable var model: NewExpenseModel
    let onCancel: () -> Void
    let onNext: () -> Void

    @State private var calculator: AmountCalculator
    @State private var showingPaymentHint = false

    init(model: NewExpenseModel, onCancel: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.model = model
        self.onCancel = onCancel
        self.onNext = onNext
        _calculator = State(initialValue: AmountCalculator(amountMinor: model.amountMinor))
    }

    private static let currencyChoices: [CurrencyCode] = [.sek, .dkk, .nok, .eur]

    var body: some View {
        VStack(spacing: 0) {
            Steven.NavTitleBar(leading: .close(onCancel)) { typeMenu }
            payerRow
            Spacer(minLength: 12)
            amountSection
            Spacer(minLength: 12)
            toolbar
            Steven.Keypad { key in press(key) }
        }
        .background(StevenColor.surface, ignoresSafeAreaEdges: .top)
        .background(StevenColor.keyboardBase.ignoresSafeArea())
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.45), trigger: calculator)
        .alert("Registrera en betalning", isPresented: $showingPaymentHint) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Öppna gruppens flik Ställning eller Betalningar och välj Betala eller Markera som betald där.")
        }
        .onChange(of: calculator.amountMinor) { _, minor in
            model.amount = AmountInput(amountMinor: minor)
        }
    }

    // MARK: - Title ⌄

    /// "UTGIFT ⌄" (12): the type switch the issue asks for. There is no second amount-entry
    /// screen for a manual payment yet, so picking "Betalning" points at the flows that already
    /// record one (STÄLLNING/BETALNINGAR, Betala/Markera som betald) instead of guessing a new
    /// write path for money here — flagged in the PR as a guess for Carl to revisit.
    private var typeMenu: some View {
        Menu {
            Button("Utgift") {}
            Button("Betalning") { showingPaymentHint = true }
        } label: {
            HStack(spacing: 6) {
                Text("Utgift")
                Image(systemName: "chevron.down").font(.system(size: 13, weight: .light))
            }
        }
    }

    // MARK: - Payer chip

    /// "(avatar) Carl betalade ›" (12): outline chip, opens the member list. Locked while
    /// editing — moving an expense to a different payer is a correction to who owes what, which
    /// belongs in the split, not a silent side effect of reopening the amount step.
    @ViewBuilder private var payerRow: some View {
        HStack {
            if model.isEditing {
                payerChipContent
            } else {
                Menu {
                    ForEach(model.members) { member in
                        Button(model.name(for: member)) { model.payerId = member.id }
                    }
                } label: {
                    payerChipContent
                }
                .accessibilityLabel(Text("Byt betalare"))
            }
            Spacer()
        }
        .padding(.horizontal, StevenMetric.gutter + 4)
        .padding(.top, 4)
    }

    @ViewBuilder private var payerChipContent: some View {
        if let payer = model.payerMember {
            HStack(spacing: 12) {
                Steven.AvatarView(member: payer, size: 24, isMe: model.isPayerMe)
                Text(payerSentence(for: payer)).stevenFont(.rowTitle)
                if !model.isEditing { Steven.Chevron() }
            }
            .foregroundStyle(StevenColor.ink)
            .padding(.horizontal, 10)
            .frame(minHeight: StevenMetric.minimumHitTarget)
            .overlay {
                RoundedRectangle(cornerRadius: StevenMetric.controlRadius)
                    .strokeBorder(StevenColor.hairline, lineWidth: 1)
            }
        }
    }

    private func payerSentence(for payer: Member) -> String {
        model.isPayerMe ? String(localized: "Du betalade") : String(localized: "\(model.name(for: payer)) betalade")
    }

    // MARK: - Amount + currency

    private var amountSection: some View {
        VStack(spacing: 6) {
            if let prefix = calculator.pendingExpression {
                Text(verbatim: prefix)
                    .stevenFont(.rowTitle)
                    .foregroundStyle(StevenColor.muted)
            }
            HStack(alignment: .center, spacing: 10) {
                Text(verbatim: calculator.display)
                    .stevenFont(.amountHero)
                    .foregroundStyle(calculator.display == "0" ? StevenColor.placeholder : StevenColor.ink)
                    .accessibilityLabel(Text("Belopp \(calculator.display) \(model.currency.code)"))
                currencyChip
            }
        }
        .padding(.horizontal, StevenMetric.gutter)
        .accessibilityElement(children: .combine)
    }

    /// "SEK ›": locked while editing, same rule as the old amount display — a correction to the
    /// amount must not quietly re-denominate it.
    @ViewBuilder private var currencyChip: some View {
        let label = Text(verbatim: model.currency.code)
            .stevenFont(.rowTitle)
            .foregroundStyle(StevenColor.ink)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .overlay {
                RoundedRectangle(cornerRadius: StevenMetric.controlRadius)
                    .strokeBorder(StevenColor.hairline, lineWidth: 1)
            }
        if model.isEditing {
            label
        } else {
            Menu {
                ForEach(Self.currencyChoices, id: \.self) { choice in
                    Button(choice.code) { model.currency = choice }
                }
            } label: {
                label
            }
            .accessibilityLabel(Text("Valuta"))
            .accessibilityValue(model.currency.code)
        }
    }

    // MARK: - Toolbar: räknare + Nästa

    /// "Verktygsrad: räknare (+−×÷) ... Nästa" (12, 13). One calculator icon rather than four
    /// loose operator buttons, matching the icon already placed here for #145's evidence shot
    /// (`Steven.Gallery`'s `GalleryAmount`) — tapping it opens the four operators as a menu.
    private var toolbar: some View {
        HStack {
            Menu {
                ForEach(AmountCalculator.Operator.allCases, id: \.self) { op in
                    Button(operatorLabel(op)) { calculator.apply(op) }
                }
            } label: {
                Image(systemName: "plus.forwardslash.minus")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(StevenColor.muted)
                    .frame(width: StevenMetric.minimumHitTarget, height: StevenMetric.minimumHitTarget)
                    .contentShape(.rect)
            }
            .accessibilityLabel(Text("Räknare"))
            Spacer()
            Button("Nästa", action: onNext)
                .buttonStyle(Steven.FilledButtonStyle(height: 38))
                .frame(width: 72)
                .disabled(calculator.amountMinor <= 0)
        }
        .padding(.horizontal, StevenMetric.gutter)
        .padding(.bottom, 8)
    }

    private func operatorLabel(_ op: AmountCalculator.Operator) -> String {
        switch op {
        case .add: String(localized: "Plus")
        case .subtract: String(localized: "Minus")
        case .multiply: String(localized: "Gånger")
        case .divide: String(localized: "Dividerat med")
        }
    }

    // MARK: - Keypad

    private func press(_ key: Steven.Key) {
        switch key {
        case .digit(let digit): calculator.input(Character("\(digit)"))
        case .decimal: calculator.comma()
        case .delete: calculator.backspace()
        }
    }
}
