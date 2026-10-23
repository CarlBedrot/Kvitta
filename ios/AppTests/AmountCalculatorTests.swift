import Foundation
import Testing
@testable import Kvitta

/// The Ny utgift calculator row (12, 13: "räknare +−×÷") is the one place this app does
/// arithmetic on money outside `Core`, so it gets the same guarantee every other amount does:
/// integers only, never a `Double`, and rounding to the nearest öre exactly once per pair.
struct AmountCalculatorTests {

    private func type(_ text: String, into calculator: inout AmountCalculator) {
        for character in text {
            switch character {
            case ",": calculator.comma()
            default: calculator.input(character)
            }
        }
    }

    @Test("12,50 + 7,50 lands on exactly 20 kr")
    func additionEvaluatesExactly() {
        var calculator = AmountCalculator()
        type("12,50", into: &calculator)
        calculator.apply(.add)
        type("7,50", into: &calculator)
        #expect(calculator.amountMinor == 2_000)
    }

    @Test("20 − 7,50 lands on exactly 12,50 kr")
    func subtractionEvaluatesExactly() {
        var calculator = AmountCalculator()
        type("20", into: &calculator)
        calculator.apply(.subtract)
        type("7,50", into: &calculator)
        #expect(calculator.amountMinor == 1_250)
    }

    @Test("12,50 × 3 is 37,50 kr, not 12,50 × 3,00 öre")
    func multiplicationScalesBackToMinorUnitsOnce() {
        var calculator = AmountCalculator()
        type("12,50", into: &calculator)
        calculator.apply(.multiply)
        type("3", into: &calculator)
        #expect(calculator.amountMinor == 3_750)
    }

    @Test("100 ÷ 4 splits to exactly 25 kr")
    func divisionEvaluatesExactly() {
        var calculator = AmountCalculator()
        type("100", into: &calculator)
        calculator.apply(.divide)
        type("4", into: &calculator)
        #expect(calculator.amountMinor == 2_500)
    }

    @Test("10 ÷ 3 rounds to the nearest öre, once")
    func divisionRoundsToNearestOre() {
        var calculator = AmountCalculator()
        type("10", into: &calculator)
        calculator.apply(.divide)
        type("3", into: &calculator)
        // 10/3 = 3,3333... kr -> 333,33... öre, rounds to 333.
        #expect(calculator.amountMinor == 333)
    }

    @Test("20 + 5 − 3 reads left to right: 22 kr, not 20 + (5 − 3)")
    func chainedOperatorsFoldLeftToRight() {
        var calculator = AmountCalculator()
        type("20", into: &calculator)
        calculator.apply(.add)
        type("5", into: &calculator)
        calculator.apply(.subtract)
        type("3", into: &calculator)
        #expect(calculator.amountMinor == 2_200)
    }

    @Test("Dividing by zero never crashes and keeps the left-hand amount")
    func divisionByZeroIsSafe() {
        var calculator = AmountCalculator()
        type("100", into: &calculator)
        calculator.apply(.divide)
        #expect(calculator.amountMinor == 10_000)
    }

    @Test("A second comma is ignored")
    func secondCommaIsIgnored() {
        var calculator = AmountCalculator()
        type("12,50", into: &calculator)
        calculator.comma()
        #expect(calculator.display == "12,50")
    }

    @Test("A third decimal digit is ignored")
    func thirdDecimalDigitIsIgnored() {
        var calculator = AmountCalculator()
        type("12,505", into: &calculator)
        #expect(calculator.display == "12,50")
        #expect(calculator.amountMinor == 1_250)
    }

    @Test("Backspacing a fresh second operand cancels the operator, not just a digit")
    func backspaceOnEmptyOperandCancelsOperator() {
        var calculator = AmountCalculator()
        type("20", into: &calculator)
        calculator.apply(.add)
        #expect(calculator.pendingOperator == .add)
        calculator.backspace()
        #expect(calculator.pendingOperator == nil)
        #expect(calculator.amountMinor == 2_000)
    }

    @Test("Nothing pending shows no expression prefix; a pending pair shows the running total")
    func pendingExpressionReflectsTheChain() {
        var calculator = AmountCalculator()
        #expect(calculator.pendingExpression == nil)
        type("12,50", into: &calculator)
        calculator.apply(.add)
        #expect(calculator.pendingExpression == "12,50 +")
    }
}
