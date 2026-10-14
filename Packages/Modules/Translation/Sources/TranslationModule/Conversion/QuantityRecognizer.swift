import Foundation

/// What a piece of text was read as.
enum Quantity: Equatable {
    case unit(UnitQuantity)
    case time(TimeQuery)
    case math(MathResult)
    case money(MoneyAmount)
}

struct Recognized: Equatable {
    /// The text it was read from.
    var source: String
    var quantity: Quantity
}

struct Recognition: Equatable {
    var items: [Recognized] = []
    /// The text is nothing but these quantities (and the separators between them), so there is nothing to translate.
    var isPure = false
}

/// Finds quantities in selected text: the whole text as one (a bare time or an expression counts), or the unambiguous
/// ones inside a sentence ("a $5 coffee", "meet at 3pm PST", "it was 30 °C").
enum QuantityRecognizer {
    /// Longer texts are not scanned: they are prose, and the scan tries many readings at every number.
    static let maxScannedLength = 2000
    /// The longest quantity, in characters: "9 giờ 30 phút sáng giờ New York".
    private static let longestQuantity = 40
    /// Readings tried in one text before the scan gives up on the rest, so a text full of numbers cannot keep the tab
    /// busy: a paragraph with a few dozen numbers needs a few hundred.
    static let scanBudget = 2500
    /// Quantities listed under a translation.
    static let maxItems = 3

    /// With `currency` false amounts of money are not quantities, since converting them needs the network and the user
    /// has not allowed that.
    static func recognize(_ text: String, currency: Bool) -> Recognition {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxScannedLength, trimmed.contains(where: \.isASCIIDigit) else { return Recognition() }
        // "What is 3+4?" and "72 °F." end in a full stop or question mark that belongs to the sentence.
        let whole = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?").union(.whitespaces))
        if let quantity = wholeQuantity(whole, currency: currency) {
            return Recognition(items: [Recognized(source: whole, quantity: quantity)], isPure: true)
        }
        return scan(Array(trimmed), currency: currency)
    }

    private static func wholeQuantity(_ text: String, currency: Bool) -> Quantity? {
        if let time = TimeQueryParser.parse(text) { return .time(time) }
        if currency, let money = CurrencyParser.parse(text) { return .money(money) }
        if let unit = UnitQuantityParser.parse(text) { return .unit(unit) }
        if case .success(let result) = MathExpression.evaluate(text), result.usesOperator, !looksLikeADateOrCode(text) {
            return .math(result)
        }
        return nil
    }

    /// "2024-10-15", "15/10/2024" and "090-123-4567" are three numbers joined by signs with no space, which nobody
    /// calculates; "2024 - 10 - 15" or "10 / 4" are still calculations.
    private static func looksLikeADateOrCode(_ text: String) -> Bool {
        text.wholeMatch(of: /\d+([-\/]\d+){2,}/) != nil
    }

    private static func scan(_ characters: [Character], currency: Bool) -> Recognition {
        var found: [Recognized] = []
        var covered = Array(repeating: false, count: characters.count)
        var start = 0
        var budget = scanBudget
        while start < characters.count, budget > 0 {
            guard canStart(characters, at: start), let (item, end) = longestQuantity(characters, from: start, currency: currency, budget: &budget) else {
                start += 1
                continue
            }
            if !found.contains(where: { $0.source == item.source }) { found.append(item) }
            for index in start..<end { covered[index] = true }
            start = end
        }
        let leftover = characters.indices.filter { !covered[$0] }.map { characters[$0] }
        // A scan that ran out of budget did not see everything, so it cannot say the text is nothing but quantities.
        let isPure = budget > 0 && !found.isEmpty && leftover.allSatisfy { !$0.isLetter && !$0.isNumber }
        return Recognition(items: Array(found.prefix(maxItems)), isPure: isPure && found.count <= maxItems)
    }

    private static let currencySymbols: Set<Character> = ["$", "€", "£", "¥", "₩", "₹", "฿", "₫"]

    /// A quantity starts at a number (with its sign), a currency symbol, or a capitalised code or symbol prefix such as
    /// "USD 12" and "US$12", and not in the middle of a word or a number ("H2O", "v1.5").
    private static func canStart(_ characters: [Character], at index: Int) -> Bool {
        let character = characters[index]
        if index > 0 {
            let previous = characters[index - 1]
            if previous.isLetter || previous.isASCIIDigit || currencySymbols.contains(previous) { return false }
            if (previous == "." || previous == ","), index > 1, characters[index - 2].isASCIIDigit { return false }
        }
        func following(_ offset: Int) -> Character? { index + offset < characters.count ? characters[index + offset] : nil }
        if currencySymbols.contains(character) { return true }
        if character.isASCIIDigit { return isFollowedByAUnit(characters, number: index) }
        if character == "-" || character == "−" || character == "+" {
            return following(1)?.isASCIIDigit == true && isFollowedByAUnit(characters, number: index + 1)
        }
        guard character.isUppercase else { return false }
        if following(1) == "$" || (following(2) == "$" && following(1)?.isUppercase == true) { return true }
        let isCode = (0..<3).allSatisfy { following($0)?.isUppercase == true }
        return isCode && (following(3) == " " || following(3)?.isASCIIDigit == true)
    }

    /// A number that is followed by another number, a punctuation mark or nothing is not a quantity, which spares
    /// the scan most of the numbers of a table or a list.
    private static func isFollowedByAUnit(_ characters: [Character], number start: Int) -> Bool {
        guard let (_, end) = VietnameseNumber.scan(characters, from: start) else { return false }
        var index = end
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        guard index < characters.count else { return false }
        let next = characters[index]
        return next.isLetter || currencySymbols.contains(next) || "°º'’′\"”″“:℃℉²".contains(next)
    }

    /// The longest reading that ends at a word boundary, trying the longest candidate first.
    private static func longestQuantity(_ characters: [Character], from start: Int, currency: Bool, budget: inout Int) -> (Recognized, Int)? {
        // A quantity is on one line.
        let lineEnd = characters[start...].firstIndex(where: \.isNewline) ?? characters.count
        var end = min(lineEnd, start + longestQuantity)
        while end > start {
            defer { end -= 1 }
            guard !characters[end - 1].isWhitespace, endsAtBoundary(characters, at: end) else { continue }
            budget -= 1
            let candidate = String(characters[start..<end])
            if let quantity = embeddedQuantity(candidate, currency: currency) {
                return (Recognized(source: candidate, quantity: quantity), end)
            }
        }
        return nil
    }

    private static func endsAtBoundary(_ characters: [Character], at end: Int) -> Bool {
        guard end < characters.count else { return true }
        let next = characters[end]
        if next.isLetter || next.isASCIIDigit { return false }
        // Not in the middle of "1,5" or "100.000".
        if next == "." || next == "," {
            return !(end + 1 < characters.count && characters[end + 1].isASCIIDigit)
        }
        return true
    }

    private static func embeddedQuantity(_ text: String, currency: Bool) -> Quantity? {
        if let time = TimeQueryParser.parse(text, requiresZone: true) { return .time(time) }
        if currency, let money = CurrencyParser.parse(text) { return .money(money) }
        if let unit = UnitQuantityParser.parse(text), unit.isUnambiguous { return .unit(unit) }
        return nil
    }
}
