import Foundation

/// An amount of money: "$12", "12 USD", "100.000đ", "5 triệu đồng".
struct MoneyAmount: Equatable {
    var value: Decimal
    /// ISO 4217 code.
    var currency: String
}

enum CurrencyCatalog {
    /// What can be read and chosen as the target: the common currencies of the rates source.
    static let codes = [
        "VND", "USD", "EUR", "GBP", "JPY", "KRW", "CNY", "SGD", "THB", "AUD", "CAD", "CHF", "HKD", "INR", "IDR", "MYR", "PHP", "TWD", "NZD",
        "SEK", "NOK", "DKK", "RUB", "BRL", "MXN", "ZAR", "AED", "SAR", "TRY", "PLN",
    ]

    private static let wholeUnits: Set<String> = ["VND", "JPY", "KRW", "IDR"]

    /// "Đồng Việt Nam", for the Settings picker.
    static func name(of code: String) -> String {
        Locale(identifier: "vi").localizedString(forCurrencyCode: code)?.capitalizedFirst ?? code
    }

    /// "300.000 ₫" for dong, which has no minor unit in use, and "12,50 USD" for the rest.
    static func format(_ value: Double, code: String) -> String {
        let digits = wholeUnits.contains(code) ? 0 : 2
        return VietnameseNumber.fixed(value, decimals: digits) + " " + (code == "VND" ? "₫" : code)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// Reads a whole text as an amount of money, with the currency before ("$12", "USD 12") or after ("12 USD", "12€",
/// "100.000đ"). Dong also takes the way people write thousands and millions: "50k đ", "5 triệu đồng", "2 tỷ VND".
enum CurrencyParser {
    /// Longest first, so "US$" is not read as "$".
    private static let symbolPrefixes: [(String, String)] = [
        ("US$", "USD"), ("HK$", "HKD"), ("NZ$", "NZD"), ("CA$", "CAD"), ("S$", "SGD"), ("A$", "AUD"), ("C$", "CAD"), ("$", "USD"),
        ("€", "EUR"), ("£", "GBP"), ("¥", "JPY"), ("₩", "KRW"), ("₹", "INR"), ("฿", "THB"), ("₫", "VND"),
    ]

    private static let symbolSuffixes: [String: String] = [
        "$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₩": "KRW", "₹": "INR", "฿": "THB", "₫": "VND", "đ": "VND", "元": "CNY", "円": "JPY",
    ]

    /// By lowercase with accents: words that mean something else once the accents are gone ("đô", "do").
    private static let accentedWords: [String: String] = [
        "đ": "VND", "đồng": "VND", "vnđ": "VND", "đô": "USD", "đô la": "USD", "đô-la": "USD", "đô la mỹ": "USD", "yên": "JPY",
        "bảng anh": "GBP", "nhân dân tệ": "CNY", "tệ": "CNY",
    ]

    /// By folded text.
    private static let plainWords: [String: String] = [
        "dong": "VND", "vnd": "VND", "do la": "USD", "dollar": "USD", "dollars": "USD", "euro": "EUR", "euros": "EUR", "yen": "JPY",
        "won": "KRW", "yuan": "CNY", "rmb": "CNY", "baht": "THB", "rupee": "INR", "rupees": "INR", "pound sterling": "GBP",
        "pounds sterling": "GBP", "bang anh": "GBP", "nhan dan te": "CNY",
    ]

    /// By folded text; only before a dong marker.
    private static let multipliers: [String: Decimal] = [
        "k": 1_000, "nghin": 1_000, "ngan": 1_000, "tr": 1_000_000, "trieu": 1_000_000, "ty": 1_000_000_000, "ti": 1_000_000_000,
    ]

    static func parse(_ text: String) -> MoneyAmount? {
        // A currency is a symbol or a word; the scan of running text asks this about every number.
        guard text.contains(where: { !$0.isASCIIDigit && !$0.isWhitespace && $0 != "." && $0 != "," }) else { return nil }
        let characters = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if let (code, afterPrefix) = prefix(characters) {
            var index = afterPrefix
            while index < characters.count, characters[index].isWhitespace { index += 1 }
            guard let (number, end) = VietnameseNumber.scan(characters, from: index) else { return nil }
            let rest = String(characters[end...]).trimmingCharacters(in: .whitespaces)
            if rest.isEmpty { return MoneyAmount(value: number, currency: code) }
            guard code == "VND", let factor = multipliers[rest.folded] else { return nil }
            return MoneyAmount(value: number * factor, currency: code)
        }
        guard let (number, end) = VietnameseNumber.scan(characters, from: 0) else { return nil }
        let rest = String(characters[end...]).trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        let words = rest.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        if words.count == 2, let factor = multipliers[String(words[0]).folded], currency(forSuffix: String(words[1])) == "VND" {
            return MoneyAmount(value: number * factor, currency: "VND")
        }
        return currency(forSuffix: rest).map { MoneyAmount(value: number, currency: $0) }
    }

    /// The currency written before the number, and where the number may start.
    private static func prefix(_ characters: [Character]) -> (code: String, end: Int)? {
        for (symbol, code) in symbolPrefixes where characters.starts(with: Array(symbol)) {
            return (code, symbol.count)
        }
        guard characters.count > 4, characters[0..<3].allSatisfy(\.isLetter) else { return nil }
        let code = String(characters[0..<3]).uppercased()
        guard CurrencyCatalog.codes.contains(code), characters[3] == " " || characters[3].isASCIIDigit else { return nil }
        return (code, 3)
    }

    private static func currency(forSuffix text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let symbol = symbolSuffixes[trimmed] { return symbol }
        if let word = accentedWords[trimmed.lowercased()] { return word }
        if trimmed.count == 3, case let code = trimmed.uppercased(), CurrencyCatalog.codes.contains(code) { return code }
        return plainWords[trimmed.folded]
    }
}
