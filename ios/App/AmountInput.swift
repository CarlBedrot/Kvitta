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
