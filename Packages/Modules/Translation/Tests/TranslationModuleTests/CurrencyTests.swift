import Foundation
import Testing
@testable import TranslationModule

@Suite struct CurrencyParserTests {
    func money(_ text: String) -> (String, String)? {
        CurrencyParser.parse(text).map { ($0.currency, "\($0.value)") }
    }

    func isMoney(_ text: String, _ code: String, _ value: String) -> Bool {
        guard let result = money(text) else { return false }
        return result.0 == code && result.1 == value
    }

    @Test(arguments: [
        ("$12", "USD", "12"), ("$ 12", "USD", "12"), ("$12.50", "USD", "12.5"), ("$12,5", "USD", "12.5"), ("$1,234.56", "USD", "1234.56"),
        ("$1.000", "USD", "1000"), ("US$12", "USD", "12"), ("12 USD", "USD", "12"), ("12 usd", "USD", "12"), ("12USD", "USD", "12"),
        ("USD 12", "USD", "12"), ("usd12", "USD", "12"), ("12 $", "USD", "12"), ("12$", "USD", "12"), ("12 đô", "USD", "12"),
        ("12 đô la", "USD", "12"), ("12 đô-la", "USD", "12"), ("12 Đô La Mỹ", "USD", "12"), ("12 dollars", "USD", "12"), ("12 dollar", "USD", "12"),
        ("12 do la", "USD", "12"),
        ("€5", "EUR", "5"), ("5€", "EUR", "5"), ("5 €", "EUR", "5"), ("5 euro", "EUR", "5"), ("5 EUR", "EUR", "5"), ("EUR 5,50", "EUR", "5.5"),
        ("£3.50", "GBP", "3.5"), ("3 GBP", "GBP", "3"), ("3 bảng Anh", "GBP", "3"), ("3 pounds sterling", "GBP", "3"),
        ("¥1000", "JPY", "1000"), ("1000 yên", "JPY", "1000"), ("1000 JPY", "JPY", "1000"), ("1.000 yen", "JPY", "1000"),
        ("₩5000", "KRW", "5000"), ("5000 won", "KRW", "5000"), ("S$5", "SGD", "5"), ("HK$10", "HKD", "10"), ("5 nhân dân tệ", "CNY", "5"),
        ("100 baht", "THB", "100"), ("฿100", "THB", "100"), ("₹100", "INR", "100"), ("CAD 20", "CAD", "20"), ("20 AUD", "AUD", "20"),
    ])
    func readsForeignMoney(text: String, code: String, value: String) {
        #expect(isMoney(text, code, value), "\(text) -> \(String(describing: money(text)))")
    }

    @Test(arguments: [
        ("100.000đ", "100000"), ("100.000 đ", "100000"), ("100.000 VND", "100000"), ("100.000 vnd", "100000"), ("100.000₫", "100000"),
        ("₫100.000", "100000"), ("100.000 đồng", "100000"), ("100.000 VNĐ", "100000"), ("100,000 VND", "100000"), ("100000đ", "100000"),
        ("100 000".replacing(" ", with: "") + " dong", "100000"), ("VND 50.000", "50000"), ("1.500.000đ", "1500000"), ("1,5 đồng", "1.5"),
        ("50k đ", "50000"), ("50k VND", "50000"), ("50K VND", "50000"), ("50 nghìn đồng", "50000"), ("50 ngàn đ", "50000"),
        ("50 nghin dong", "50000"), ("5 triệu đồng", "5000000"), ("5tr đ", "5000000"), ("2,5 triệu VND", "2500000"), ("2 tỷ đồng", "2000000000"),
        ("1,5 tỉ đ", "1500000000"), ("₫5 triệu", "5000000"),
    ])
    func readsDong(text: String, value: String) {
        #expect(isMoney(text, "VND", value), "\(text) -> \(String(describing: money(text)))")
    }

    @Test(arguments: [
        "", "12", "USD", "$", "12 XYZ", "12 k", "50k", "5 triệu", "1,5 tỷ", "12 do", "12 d", "12 đ đ", "1.2.3 USD", "$$12", "12 USD 5", "USD USD",
        "$12 USD", "abc 12 USD", "12 pounds", "12 kg", "-$5", "12 bảng", "$12 triệu", "€5 triệu", "12 triệu USD", "12 k USD", "ab 5", "5 tr",
        "$ 1.2.3", "12.", "12 thousand", "12,5,5 USD", "USD12abc", "12 usdx",
    ])
    func refusesWhatIsNotAnAmount(text: String) {
        #expect(CurrencyParser.parse(text) == nil, "\(text) -> \(String(describing: money(text)))")
    }

    @Test func formatsAmountsTheVietnameseWay() {
        #expect(CurrencyCatalog.format(300_000, code: "VND") == "300.000 ₫")
        #expect(CurrencyCatalog.format(138_888.888, code: "VND") == "138.889 ₫")
        #expect(CurrencyCatalog.format(12.5, code: "USD") == "12,50 USD")
        #expect(CurrencyCatalog.format(4, code: "USD") == "4,00 USD")
        #expect(CurrencyCatalog.format(1_234_567.891, code: "EUR") == "1.234.567,89 EUR")
        #expect(CurrencyCatalog.format(1500.4, code: "JPY") == "1.500 JPY")
        #expect(CurrencyCatalog.format(0.004, code: "USD") == "0,00 USD")
    }

    @Test func everyCodeHasAName() {
        for code in CurrencyCatalog.codes { #expect(!CurrencyCatalog.name(of: code).isEmpty) }
        #expect(CurrencyCatalog.name(of: "VND") == "Đồng Việt Nam")
        #expect(CurrencyCatalog.name(of: "USD") == "Đô la Mỹ")
        #expect(CurrencyCatalog.name(of: "XXX").isEmpty == false)
        #expect(Set(CurrencyCatalog.codes).count == CurrencyCatalog.codes.count)
    }
}

@Suite struct ExchangeRatesModelTests {
    let rates = ExchangeRates(
        rates: ["USD": 1, "VND": 25_000, "EUR": 0.9, "JPY": 150, "BAD": 0], rateDate: utc("2026-10-14T00:02:31Z"), fetchedAt: utc("2026-10-14T08:00:00Z")
    )

    @Test func convertsThroughTheDollar() throws {
        #expect(try #require(rates.convert(12, from: "USD", to: "VND")) == 300_000)
        #expect(abs(try #require(rates.convert(5, from: "EUR", to: "VND")) - 138_888.888_888) < 0.001)
        #expect(abs(try #require(rates.convert(100_000, from: "VND", to: "USD")) - 4) < 1e-9)
        #expect(abs(try #require(rates.convert(1500, from: "JPY", to: "EUR")) - 9) < 1e-9)
        #expect(try #require(rates.convert(7, from: "USD", to: "USD")) == 7)
    }

    @Test func refusesACurrencyItHasNoRateFor() {
        #expect(rates.convert(1, from: "USD", to: "XYZ") == nil)
        #expect(rates.convert(1, from: "XYZ", to: "USD") == nil)
        #expect(rates.convert(1, from: "BAD", to: "USD") == nil)
        #expect(rates.convert(1, from: "USD", to: "BAD") == nil)
    }
}
