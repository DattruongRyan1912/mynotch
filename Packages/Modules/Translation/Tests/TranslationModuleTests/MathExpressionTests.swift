import Foundation
import Testing
@testable import TranslationModule

@Suite struct MathExpressionTests {
    func value(_ text: String) -> Decimal? {
        if case .success(let result) = MathExpression.evaluate(text) { return result.value }
        return nil
    }

    func failure(_ text: String) -> MathError? {
        if case .failure(let error) = MathExpression.evaluate(text) { return error }
        return nil
    }

    func decimal(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
    }

    @Test(arguments: [
        ("2+3*4", "14"), ("(2+3)*4", "20"), ("2*3+4*5", "26"), ("2+3*4^2", "50"), ("10-4-3", "3"), ("100/10/5", "2"),
        ("2^3^2", "512"), ("-2^2", "-4"), ("(-2)^2", "4"), ("2^-2", "0.25"), ("2*-3", "-6"), ("--3", "3"), ("+3+4", "7"),
        ("8/2*4", "16"), ("2*(3+4)*(5-1)", "56"), ("((((7))))+1", "8"), ("10 % 3 * 2", "2"), ("1+2*3-4/2", "5"),
    ])
    func followsTheUsualPrecedence(text: String, expected: String) {
        #expect(value(text) == decimal(expected))
    }

    @Test(arguments: [
        ("6×7", "42"), ("84÷2", "42"), ("9−4", "5"), ("7*6", "42"), ("42/6", "7"), ("17%5", "2"), ("-17%5", "-2"),
        ("17,5%5", "2.5"), ("2 × (3 + 4)", "14"), ("1 000 ÷ 4", "250"), ("1 2 ÷ 4", ""),
    ])
    func readsTheSignsPeopleType(text: String, expected: String) {
        #expect(value(text) == (expected.isEmpty ? nil : decimal(expected)))
    }

    @Test(arguments: [
        ("200*15%", "30"), ("100+10%", "110"), ("100-10%", "90"), ("200+50%+10%", "330"), ("50%*3", "1.5"), ("-10%*50", "-5"),
        ("(50)%", "0.5"), ("50%", "0.5"), ("10%+5%", "0.15"), ("10% + 5% + 5%", "0.1575"),
    ])
    func aPercentIsAPercentOfTheLeftSideInASumAndAHundredthElsewhere(text: String, expected: String) {
        #expect(value(text) == decimal(expected))
    }

    @Test(arguments: [
        ("1,5+2,5", "4"), ("0,1+0,2", "0.3"), ("0.1+0.2", "0.3"), ("1.000+2.000", "3000"), ("1.234,5*2", "2469"),
        ("3.5*2", "7"), ("2,5*2,5", "6.25"), ("1,000.5+1", "1001.5"), ("0,5/0,25", "2"), ("1.000.000*1.000.000", "1000000000000"),
    ])
    func addsDecimalsExactlyWithCommaOrDot(text: String, expected: String) {
        #expect(value(text) == decimal(expected))
    }

    @Test func divisionKeepsManyDigits() throws {
        let third = try #require(value("1/3"))
        #expect(third > decimal("0.33333333333333333333") && third < decimal("0.33333333333333333334"))
        #expect(value("2^0,5").map { abs(NSDecimalNumber(decimal: $0).doubleValue - 2.0.squareRoot()) < 1e-12 } == true)
    }

    @Test(arguments: [" 2 + 3 ", "2+ 3", "\t2\n+\n3", "2 +3", "\u{00A0}2+3"])
    func ignoresSpaces(text: String) {
        #expect(value(text) == 5)
    }

    @Test func countsOnlyRealCalculations() {
        func used(_ text: String) -> Bool? {
            if case .success(let result) = MathExpression.evaluate(text) { return result.usesOperator }
            return nil
        }
        #expect(used("5") == false)
        #expect(used("(5)") == false)
        #expect(used("-5") == false)
        #expect(used("50%") == false)
        #expect(used("1.000") == false)
        #expect(used("2+3") == true)
        #expect(used("(2)*3") == true)
        #expect(used("2^2") == true)
        #expect(used("7%2") == true)
    }

    @Test(arguments: ["2+", "*3", "(2+3", "2+3)", "()", "2 3", "2++", "2*/3", "1.2.3+1", "15.10.2024+1", "2(3)", "(2)(3)", "3 x 4", "^2", "2^"])
    func refusesBrokenExpressions(text: String) {
        #expect(failure(text) == .syntax)
    }

    @Test func refusesEmptyText() {
        #expect(failure("") == .empty)
        #expect(failure("  \n ") == .empty)
    }

    @Test(arguments: [
        "abc", "2+a", "pi*2", "sqrt(4)", "1e3", "0x10", "2**3", "a=1", "\"2\"+\"3\"", "1;2", "1,2,3", "$(echo hi)", "`ls`",
        "system(\"ls\")", "__import__('os')", "FUNCTION(1,'a','b')", "1 + $x", "2 ** 3", "1 & 2", "1 | 2", "~1", "!1", "1 < 2",
        "NSExpression", "(1+1)==2", "{1}", "[1]", "2²", "٣+٣", "1\\n+1", "1 // 2", "2 ⁄ 4",
    ])
    func runsNothingButArithmetic(text: String) {
        #expect(failure(text) == .syntax)
    }

    @Test func refusesWhatItCannotCalculate() {
        #expect(failure("1/0") == .divisionByZero)
        #expect(failure("1/(2-2)") == .divisionByZero)
        #expect(failure("5%0") == .divisionByZero)
        #expect(failure("0^-1") == .divisionByZero)
        #expect(failure("10^400") == .outOfRange)
        #expect(failure("9^9^9") == .outOfRange)
        #expect(failure("10^1000000") == .outOfRange)
        #expect(failure("(-8)^0,5") == .outOfRange)
        let big = String(repeating: "9", count: 30)
        #expect(failure("\(big)*\(big)*\(big)*\(big)*\(big)*\(big)") == .outOfRange)
    }

    @Test func staysWithinItsLimits() {
        let deep = String(repeating: "(", count: 99) + "1" + String(repeating: ")", count: 99)
        #expect(failure(deep) == .tooComplex)
        let fine = String(repeating: "(", count: 60) + "1" + String(repeating: ")", count: 60)
        #expect(value(fine) == 1)
        let unary = String(repeating: "-", count: 150) + "1"
        #expect(failure(unary) == .tooComplex)
        let long = String(repeating: "1+", count: 100) + "1"
        #expect(failure(long) == .tooLong)
        let sum = String(repeating: "1+", count: 90) + "1"
        #expect(value(sum) == 91)
    }

    @Test func powersOfZeroAndOne() {
        #expect(value("0^0") == 1)
        #expect(value("0^5") == 0)
        #expect(value("5^0") == 1)
        #expect(value("1^1000000") == 1)
        #expect(value("2^10") == 1024)
        #expect(value("2^-1") == decimal("0.5"))
        #expect(value("10^15") == decimal("1000000000000000"))
    }
}
