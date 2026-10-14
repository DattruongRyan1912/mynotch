import Foundation
import Testing
@testable import TranslationModule

@Suite struct VietnameseNumberTests {
    func value(_ text: String) -> Decimal? {
        VietnameseNumber.scan(Array(text), from: 0).flatMap { $0.end == text.count ? $0.value : nil }
    }

    @Test(arguments: [
        ("12", "12"), ("0", "0"), ("12,5", "12.5"), ("12.5", "12.5"), ("1.23", "1.23"), ("1234,5", "1234.5"),
        ("1234.567", "1234.567"),
        // A lone separator before exactly three digits is a thousands separator: "100.000đ" is a hundred thousand.
        ("100.000", "100000"), ("2.500", "2500"), ("1,000", "1000"), ("999.999", "999999"),
        ("1.000.000", "1000000"), ("12,345,678", "12345678"),
        // But not after a leading zero, where it can only be a decimal.
        ("0,500", "0.5"), ("0.500", "0.5"),
        // Both kinds: the last one is the decimal separator.
        ("1.234,56", "1234.56"), ("1,234.56", "1234.56"), ("1.234.567,89", "1234567.89"), ("1,234,567.89", "1234567.89"),
    ])
    func readsEitherConvention(text: String, expected: String) {
        #expect(value(text) == Decimal(string: expected, locale: Locale(identifier: "en_US_POSIX")))
    }

    @Test(arguments: ["1.2.3", "15.10.2024", "1,5,5", "1.23.456", "1,234.5,6", "01.000.000", "1.0000.000"])
    func refusesWhatIsNotANumber(text: String) {
        #expect(VietnameseNumber.scan(Array(text), from: 0) == nil)
    }

    @Test func stopsAtTheEndOfTheNumber() throws {
        let text = Array("12. Next 3,5kg 7,")
        let first = try #require(VietnameseNumber.scan(text, from: 0))
        #expect(first.end == 2)
        let second = try #require(VietnameseNumber.scan(text, from: 9))
        #expect(second.value == Decimal(string: "3.5") && second.end == 12)
        let third = try #require(VietnameseNumber.scan(text, from: 15))
        #expect(third.value == 7 && third.end == 16)
        #expect(VietnameseNumber.scan(text, from: 3) == nil)
        #expect(VietnameseNumber.scan(text, from: 99) == nil)
    }

    @Test func leavesNonAsciiDigitsAlone() {
        #expect(VietnameseNumber.scan(Array("٣"), from: 0) == nil)
        #expect(VietnameseNumber.scan(Array("²"), from: 0) == nil)
    }

    @Test(arguments: [
        (180.34, "180"), (22.222, "22"), (0.9072, "0,91"), (1.609, "1,61"), (2.54, "2,54"), (1234.5, "1.235"),
        (0.0456, "0,046"), (9.999, "10"), (0.0, "0"), (-22.2, "-22"), (1_000_000.0, "1.000.000"), (5.0, "5"),
        (3.785, "3,79"), (-0.4, "-0,4"), (0.00004, "0,00004"), (99.5, "100"),
    ])
    func quickResultsKeepTwoSignificantDigitsAtMost(value: Double, expected: String) {
        // Whole numbers from 10 up, two decimals from 1 to 10, two significant digits below 1.
        #expect(VietnameseNumber.quick(value) == expected)
    }

    @Test func quickNeverShowsANegativeZero() {
        #expect(VietnameseNumber.quick(-0.0000000001) == "0")
        #expect(VietnameseNumber.quick(-0.001) == "-0,001")
    }

    @Test func fixedKeepsTheZeros() {
        #expect(VietnameseNumber.fixed(12.5, decimals: 2) == "12,50")
        #expect(VietnameseNumber.fixed(300_000, decimals: 0) == "300.000")
        #expect(VietnameseNumber.fixed(1_234_567.891, decimals: 2) == "1.234.567,89")
        #expect(VietnameseNumber.fixed(-999.5, decimals: 0) == "-1.000")
    }

    @Test(arguments: [
        ("14", "14"), ("0.3", "0,3"), ("0.3333333333333333333333333333", "0,3333333333"), ("1234.5", "1.234,5"),
        ("-3.5", "-3,5"), ("1000000", "1.000.000"), ("0.00000000001", "0"), ("100000000000000", "100.000.000.000.000"),
        ("1000000000000000", "1e15"), ("-2500000000000000000000", "-2,5e21"), ("0.1234567891234", "0,1234567891"),
    ])
    func decimalsAreRoundedAndGrouped(text: String, expected: String) throws {
        let decimal = try #require(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")))
        #expect(VietnameseNumber.format(decimal) == expected)
    }
}
