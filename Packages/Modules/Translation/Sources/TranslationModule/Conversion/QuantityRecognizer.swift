import Foundation

/// What a piece of text was read as.
nonisolated enum Quantity: Equatable {
    case unit(UnitQuantity)
    case time(TimeQuery)
    case math(MathResult)
    case money(MoneyAmount)
}

nonisolated struct Recognized: Equatable {
    /// The text it was read from.
    var source: String
    var quantity: Quantity
}

nonisolated struct Recognition: Equatable {
    var items: [Recognized] = []
    /// The text is nothing but these quantities (and the separators between them), so there is nothing to translate.
    var isPure = false
}

/// Finds quantities in selected text: the whole text as one, or the unambiguous ones inside a sentence ("a $5 coffee",
/// "meet at 3pm PST", "it was 30 °C"). It offers only what is clearly a quantity, since an offer replaces the translation
/// when the text is nothing else:
///
/// - units with a unit word or symbol, a single quantity or a range with both ends ("5-10 kg");
/// - times with an explicit zone (see `TimeZoneCatalog.explicitZone`), never a bare "3pm" or a bare city;
/// - calculations written with `+ * × ÷ ^`, a leading "=", or a "-" or "/" with a space on each side, never "3-4" or "1/2";
/// - amounts of money, when the user allowed converting them.
nonisolated enum QuantityRecognizer {
    /// Only selections this short are looked at: a quantity is a few words, a longer selection is prose, and the scan
    /// tries many readings at every number.
    static let maxSelectionLength = 200
    /// The longest quantity, in characters: "9 giờ 30 phút sáng giờ New York".
    private static let longestQuantity = 40
    /// Quantities listed under a translation.
    static let maxItems = 3

    /// With `currency` false amounts of money are not quantities, since converting them needs the network and the user
    /// has not allowed that. A cancelled task gets nothing, so the scan stops when a newer selection replaces its text.
    static func recognize(_ text: String, currency: Bool) -> Recognition {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxSelectionLength, trimmed.contains(where: \.isASCIIDigit) else { return Recognition() }
        // "What is 3+4?" and "72 °F." end in a mark that belongs to the sentence. Only the end: ".5 kg" starts with a point.
        var whole = Substring(trimmed)
        while let last = whole.last, ".,;:!? ".contains(last) { whole = whole.dropLast() }
        if let found = wholeQuantity(String(whole), currency: currency) {
            return Recognition(items: [found], isPure: true)
        }
        return scan(Array(trimmed), currency: currency)
    }

    private static func wholeQuantity(_ text: String, currency: Bool) -> Recognized? {
        if let time = TimeQueryParser.parse(text) { return Recognized(source: text, quantity: .time(time)) }
        if currency, let money = CurrencyParser.parse(text) { return Recognized(source: text, quantity: .money(money)) }
        if let unit = UnitQuantityParser.parse(text) { return Recognized(source: text, quantity: .unit(unit)) }
        guard let expression = explicitExpression(text), case .success(let result) = MathExpression.evaluate(expression),
              result.usesOperator else { return nil }
        return Recognized(source: expression, quantity: .math(result))
    }

    /// The expression in `text` if it asks to be calculated, without its "=": a "=" at either end, any of `+ * × ÷ ^`, or
    /// a "-", "−" or "/" with whitespace on both sides. A bare "3-4" is a range or a score, "12/10" a date or a fraction,
    /// "15 % 4" nothing a reader would ask to calculate.
    private static func explicitExpression(_ text: String) -> String? {
        var body = Substring(text)
        var isExplicit = false
        if body.first == "=" {
            body = body.dropFirst()
            isExplicit = true
        }
        if body.last == "=" {
            body = body.dropLast()
            isExplicit = true
        }
        let expression = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else { return nil }
        if isExplicit || expression.contains(where: { "+*×÷^".contains($0) }) { return expression }
        let characters = Array(expression)
        let hasSpacedSign = characters.indices.contains { index in
            "-−/".contains(characters[index]) && index > 0 && index + 1 < characters.count
                && characters[index - 1].isWhitespace && characters[index + 1].isWhitespace
        }
        return hasSpacedSign ? expression : nil
    }

    private static func scan(_ characters: [Character], currency: Bool) -> Recognition {
        var found: [Recognized] = []
        var covered = Array(repeating: false, count: characters.count)
        var start = 0
        while start < characters.count, !Task.isCancelled {
            guard canStart(characters, at: start), let (item, end) = longestQuantity(characters, from: start, currency: currency) else {
                start += 1
                continue
            }
            if !found.contains(where: { $0.source == item.source }) { found.append(item) }
            for index in start..<end { covered[index] = true }
            start = end
        }
        guard !Task.isCancelled else { return Recognition() }
        let leftover = characters.indices.filter { !covered[$0] }.map { characters[$0] }
        let isPure = !found.isEmpty && leftover.allSatisfy { !$0.isLetter && !$0.isNumber }
        return Recognition(items: Array(found.prefix(maxItems)), isPure: isPure && found.count <= maxItems)
    }

    private static let currencySymbols: Set<Character> = ["$", "€", "£", "¥", "₩", "₹", "฿", "₫"]
    private static let rangeSigns: Set<Character> = ["-", "–", "—", "~", "−"]
    private static let spaces: Set<Character> = [" ", "\u{00A0}", "\u{202F}", "\u{2009}"]

    /// A quantity starts at a number (with its sign), a currency symbol, or a capitalised code or symbol prefix such as
    /// "USD 12" and "US$12", and not in the middle of a word or a number ("H2O", "v1.5"), and never where it would drop the
    /// front of what it belongs to: the "1" of "1 5000 kg", the ".", of ".5 kg", the "5" of "5-10 apples".
    private static func canStart(_ characters: [Character], at index: Int) -> Bool {
        let character = characters[index]
        if index > 0 {
            let previous = characters[index - 1]
            if previous.isLetter || previous.isASCIIDigit || currencySymbols.contains(previous) { return false }
            if previous == "." || previous == "," { return false }
            if followsADigitOrADash(characters, before: index) { return false }
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

    /// Whether what comes before `index`, past any spaces, is a digit (so this is the tail of digits that were not read as
    /// one number, "1 5000" or "12  500"), or a dash that follows a digit (so this is the upper end of a range that was
    /// not read, "5-10 apples" or "5 - 10 USD").
    private static func followsADigitOrADash(_ characters: [Character], before index: Int) -> Bool {
        var cursor = index - 1
        while cursor >= 0, characters[cursor].isWhitespace || spaces.contains(characters[cursor]) { cursor -= 1 }
        guard cursor >= 0 else { return false }
        if characters[cursor].isASCIIDigit { return cursor < index - 1 }
        guard rangeSigns.contains(characters[cursor]) else { return false }
        cursor -= 1
        while cursor >= 0, characters[cursor].isWhitespace { cursor -= 1 }
        return cursor >= 0 && characters[cursor].isASCIIDigit
    }

    /// A number that is followed by another number, a punctuation mark or nothing is not a quantity, which spares
    /// the scan most of the numbers of a table or a list.
    private static func isFollowedByAUnit(_ characters: [Character], number start: Int) -> Bool {
        guard let (_, end) = VietnameseNumber.scan(characters, from: start) else { return false }
        var index = end
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        guard index < characters.count else { return false }
        let next = characters[index]
        // A range goes on to its upper end: "5-10 kg", "5 to 10 kg".
        return next.isLetter || currencySymbols.contains(next) || rangeSigns.contains(next) || "°º'’′\"”″“:℃℉²".contains(next)
    }

    /// The longest reading that ends at a word boundary, trying the longest candidate first.
    private static func longestQuantity(_ characters: [Character], from start: Int, currency: Bool) -> (Recognized, Int)? {
        // A quantity is on one line.
        let lineEnd = characters[start...].firstIndex(where: \.isNewline) ?? characters.count
        var end = min(lineEnd, start + longestQuantity)
        while end > start, !Task.isCancelled {
            defer { end -= 1 }
            // A quantity does not end in the comma or full stop of its sentence.
            guard !characters[end - 1].isWhitespace, !",;:.!?".contains(characters[end - 1]),
                  endsAtBoundary(characters, at: end) else { continue }
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
        if let time = TimeQueryParser.parse(text) { return .time(time) }
        if currency, let money = CurrencyParser.parse(text) { return .money(money) }
        if let unit = UnitQuantityParser.parse(text), unit.isUnambiguous { return .unit(unit) }
        return nil
    }
}
