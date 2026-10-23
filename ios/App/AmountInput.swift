import Foundation

/// The state behind the Swish-style keypad. Krona digits typed left-to-right, then an optional
/// comma and up to two öre digits — the mockup shows "437 kr", not a cents-from-the-right ticker.
///
/// A pure value type doing integer arithmetic only: `amountMinor` is what the expense is built
/// from, and it never passes through a `Double`.
struct AmountInput: Equatable {
    private(set) var kronor: String = ""
    private(set) var ore: String = ""
    private(set) var hasComma: Bool = false

    /// Cap kronor length so the amount stays well inside `Int64` minor units.
    private static let maxKronorDigits = 9

    init() {}

    /// Prefilled state for editing an existing expense: `43_759` → "437,59", `43_700` → "437".
    init(amountMinor: Int64) {
        let magnitude = max(0, amountMinor)
        kronor = magnitude / 100 == 0 ? "" : "\(magnitude / 100)"
        let oreValue = magnitude % 100
        if oreValue != 0 {
            hasComma = true
            if kronor.isEmpty { kronor = "0" }
            ore = oreValue < 10 ? "0\(oreValue)" : "\(oreValue)"
        }
    }

    /// The amount in minor units (öre). A trailing single öre digit means tenths: "5" → 50 öre.
    var amountMinor: Int64 {
        let k = Int64(kronor) ?? 0
        let o: Int64
        switch ore.count {
        case 1: o = (Int64(ore) ?? 0) * 10
        case 2: o = Int64(ore) ?? 0
        default: o = 0
        }
        return k * 100 + o
    }

    var isEmpty: Bool { kronor.isEmpty && !hasComma }

    /// What the big amount label shows. Reflects keypad state literally so a lone comma reads
    /// "437," while the user is mid-entry.
    var display: String {
        let k = kronor.isEmpty ? "0" : kronor
        return hasComma ? "\(k),\(ore)" : k
    }

    mutating func input(_ digit: Character) {
        guard digit.isNumber else { return }
        if hasComma {
            if ore.count < 2 { ore.append(digit) }
        } else if kronor == "0" {
            // No leading zeros: the first non-zero digit replaces a lone "0".
            kronor = digit == "0" ? "0" : String(digit)
        } else if kronor.count < Self.maxKronorDigits {
            kronor.append(digit)
        }
    }

    mutating func comma() {
        hasComma = true
        if kronor.isEmpty { kronor = "0" }
    }

    mutating func backspace() {
        if hasComma, !ore.isEmpty {
            ore.removeLast()
        } else if hasComma {
            hasComma = false
        } else if !kronor.isEmpty {
            kronor.removeLast()
        }
    }
}

/// The amount field's calculator chain (Ny utgift steg 1, 12/13: "räknare +−×÷"). Two operands
/// at a time, evaluated left to right with no precedence — a pocket calculator, not a parser —
/// and everything is `Int64` minor units. There is no Double anywhere: multiplying or dividing
/// two fixed-point amounts (each already "× 100") needs exactly one division by 100 to land back
/// in minor units, and that division is the single rounding step the issue asks for.
struct AmountCalculator: Equatable {
    enum Operator: Hashable, CaseIterable {
        case add, subtract, multiply, divide

        var symbol: String {
            switch self {
            case .add: "+"
            case .subtract: "−"
            case .multiply: "×"
            case .divide: "÷"
            }
        }
    }

    private(set) var operand = AmountInput()
    private var accumulatedMinor: Int64 = 0
    private(set) var pendingOperator: Operator?
    private var hasAccumulated = false

    init() {}

    /// Prefilled for editing an existing expense: no chain, just the stored amount.
    init(amountMinor: Int64) {
        operand = AmountInput(amountMinor: amountMinor)
    }

    /// What the hero label shows right now: the operand being typed.
    var display: String { operand.display }

    /// "12,50 +" while a second operand is being typed, so the running total is not lost from
    /// view mid-chain. `nil` once nothing is pending.
    var pendingExpression: String? {
        guard let pendingOperator else { return nil }
        return "\(AmountInput(amountMinor: accumulatedMinor).display) \(pendingOperator.symbol)"
    }

    /// The value the sheet actually uses: the pending pair evaluated if there is one, otherwise
    /// just the typed operand. Live, not only at `Nästa` — so "Nästa" enables the instant a chain
    /// resolves to something positive.
    var amountMinor: Int64 {
        guard let pendingOperator else { return operand.amountMinor }
        return Self.evaluate(hasAccumulated ? accumulatedMinor : 0, pendingOperator, operand.amountMinor)
    }

    mutating func input(_ digit: Character) { operand.input(digit) }
    mutating func comma() { operand.comma() }

    /// Starting a new pair folds any pair already pending into the accumulator first, so
    /// "20+5-3" reads left to right instead of only ever remembering the last two keys.
    mutating func apply(_ nextOperator: Operator) {
        accumulatedMinor = pendingOperator.map { Self.evaluate(accumulatedMinor, $0, operand.amountMinor) }
            ?? operand.amountMinor
        hasAccumulated = true
        pendingOperator = nextOperator
        operand = AmountInput()
    }

    /// Backspacing a fresh, empty second operand cancels the pending operator and goes back to
    /// editing the accumulated amount — a calculator's ⌫ stepping back one key, not just one digit.
    mutating func backspace() {
        if operand.isEmpty, pendingOperator != nil {
            pendingOperator = nil
            operand = AmountInput(amountMinor: accumulatedMinor)
        } else {
            operand.backspace()
        }
    }

    static func evaluate(_ lhsMinor: Int64, _ op: Operator, _ rhsMinor: Int64) -> Int64 {
        switch op {
        case .add: return lhsMinor + rhsMinor
        case .subtract: return lhsMinor - rhsMinor
        case .multiply: return roundedQuotient(lhsMinor * rhsMinor, 100)
        case .divide:
            guard rhsMinor != 0 else { return lhsMinor }
            return roundedQuotient(lhsMinor * 100, rhsMinor)
        }
    }

    /// Nearest-integer division (half away from zero), in `Int64` only.
    private static func roundedQuotient(_ numerator: Int64, _ denominator: Int64) -> Int64 {
        let sign: Int64 = (numerator < 0) == (denominator < 0) ? 1 : -1
        let n = numerator.magnitude, d = denominator.magnitude
        let quotient = n / d, remainder = n % d
        let rounded = remainder * 2 >= d ? quotient + 1 : quotient
        return sign * Int64(rounded)
    }
}
