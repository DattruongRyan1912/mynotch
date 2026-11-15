import Foundation

/// A number with a unit, such as "5 ft 11 in" (as 5,92 ft) or "72 °F", or a range of them, such as "5-10 kg".
nonisolated struct UnitQuantity: Equatable {
    var value: Double
    /// The other end of a range ("5-10 kg" is 5 and 10), in the same unit; nil for a single quantity.
    var upper: Double?
    var unit: MeasureUnit
    /// Safe to take from running text: it did not rest on a one-letter unit, a quote mark or "in".
    var isUnambiguous: Bool

    init(value: Double, upper: Double? = nil, unit: MeasureUnit, isUnambiguous: Bool) {
        self.value = value
        self.upper = upper
        self.unit = unit
        self.isUnambiguous = isUnambiguous
    }
}

/// Reads a whole text as a quantity: sign, then a number and its unit, and for lengths, masses and volumes more such
/// pairs of smaller units ("5 ft 11 in", "5'11\"", "1 lb 8 oz"). A bare number after feet counts as inches. Or as a range
/// of one unit with both ends ("5-10 kg", "5 – 10 kg", "5 to 10 kg", "từ 5 đến 10 kg" without the "từ", "-5 đến 10 °C").
nonisolated enum UnitQuantityParser {
    static func parse(_ text: String) -> UnitQuantity? {
        let characters = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if let range = parseRange(characters) { return range }
        return parseQuantity(characters)
    }

    private static func parseQuantity(_ characters: [Character]) -> UnitQuantity? {
        var index = 0
        var sign = 1.0
        if index < characters.count, let written = signValue(characters[index]) {
            sign = written
            index = skippingSpaces(characters, from: index + 1)
        }
        var segments: [(value: Double, unit: MeasureUnit?)] = []
        var isUnambiguous = true
        while index < characters.count {
            guard let (number, afterNumber) = VietnameseNumber.scan(characters, from: index) else { return nil }
            let (unitText, afterUnit, afterSpace) = readUnit(characters, from: afterNumber)
            var unit: MeasureUnit?
            if !unitText.isEmpty {
                guard let match = UnitCatalog.match(unitText, afterSpace: afterSpace) else { return nil }
                unit = match.unit
                isUnambiguous = isUnambiguous && match.isUnambiguous
            }
            segments.append((NSDecimalNumber(decimal: number).doubleValue, unit))
            index = skippingSpaces(characters, from: afterUnit)
        }
        guard let first = segments.first, let firstUnit = first.unit else { return nil }
        var total = first.value
        var previous = firstUnit
        for segment in segments.dropFirst() {
            guard let unit = segment.unit ?? (previous == UnitCatalog.foot ? UnitCatalog.inch : nil),
                  [.length, .mass, .volume].contains(firstUnit.category), unit.category == firstUnit.category,
                  unit.base(1) < previous.base(1) else { return nil }
            total += Measurement(value: segment.value, unit: unit.dimension).converted(to: firstUnit.dimension).value
            previous = unit
        }
        return UnitQuantity(value: sign * total, unit: firstUnit, isUnambiguous: isUnambiguous || segments.count > 1)
    }

    /// Words and signs between the two ends of a range.
    private static let rangeWords: Set<String> = ["to", "đến", "tới"]
    private static let rangeSigns: Set<Character> = ["-", "–", "—", "~", "−"]

    /// "5-10 kg", "5 kg - 10 kg", "5 to 10 kg": the first end may carry the unit or not, the second must, and when both do
    /// it is the same. Anything else after the second end, or a second unit that differs, is not a range.
    private static func parseRange(_ characters: [Character]) -> UnitQuantity? {
        var index = 0
        let lowerSign = leadingSign(characters, &index)
        guard let (lowerNumber, afterLower) = VietnameseNumber.scan(characters, from: index) else { return nil }
        var (unitText, afterUnit, afterSpace) = readUnit(characters, from: afterLower)
        // The separator is the end of what was read as the first unit.
        guard let separator = trailingSeparator(of: unitText) else { return nil }
        unitText = String(unitText.dropLast(separator.count)).trimmingCharacters(in: .whitespaces)
        let lowerMatch = unitText.isEmpty ? nil : UnitCatalog.match(unitText, afterSpace: afterSpace)
        guard unitText.isEmpty || lowerMatch != nil else { return nil }

        index = skippingSpaces(characters, from: afterUnit)
        let upperSign = leadingSign(characters, &index, allowingSpace: false)
        guard let (upperNumber, afterUpper) = VietnameseNumber.scan(characters, from: index) else { return nil }
        let (upperText, afterUpperUnit, upperAfterSpace) = readUnit(characters, from: afterUpper)
        guard !upperText.isEmpty, let upperMatch = UnitCatalog.match(upperText, afterSpace: upperAfterSpace),
              skippingSpaces(characters, from: afterUpperUnit) == characters.count,
              lowerMatch == nil || lowerMatch?.unit == upperMatch.unit else { return nil }
        return UnitQuantity(
            value: lowerSign * NSDecimalNumber(decimal: lowerNumber).doubleValue,
            upper: upperSign * NSDecimalNumber(decimal: upperNumber).doubleValue,
            unit: upperMatch.unit,
            isUnambiguous: upperMatch.isUnambiguous && (lowerMatch?.isUnambiguous ?? true)
        )
    }

    /// The range sign or word that ends `text` as a word of its own ("kg -", "-", "to"), or nil.
    private static func trailingSeparator(of text: String) -> String? {
        guard let last = text.last else { return nil }
        if rangeSigns.contains(last) { return String(last) }
        let words = text.split(whereSeparator: \.isWhitespace)
        guard let word = words.last, rangeWords.contains(String(word).lowercased()), text.hasSuffix(word) else { return nil }
        return String(word)
    }

    /// A sign before a number; moves `index` past it. A sign may be followed by spaces only for the first end ("- 5").
    private static func leadingSign(_ characters: [Character], _ index: inout Int, allowingSpace: Bool = true) -> Double {
        guard index < characters.count, let written = signValue(characters[index]) else { return 1 }
        let next = index + 1
        if !allowingSpace, !(next < characters.count && characters[next].isASCIIDigit) { return 1 }
        index = allowingSpace ? skippingSpaces(characters, from: next) : next
        return written
    }

    private static func signValue(_ character: Character) -> Double? {
        switch character {
        case "-", "−": -1
        case "+": 1
        default: nil
        }
    }

    private static func skippingSpaces(_ characters: [Character], from start: Int) -> Int {
        var index = start
        while index < characters.count, characters[index].isWhitespace { index += 1 }
        return index
    }

    /// The unit that follows a number: up to the next number, or a space and a number. A "2" or "3" that ends a word
    /// belongs to it ("m2", "ft3"), unless a letter follows ("ft2in" is 2 inches). Also says whether a space came
    /// between the number and the unit.
    private static func readUnit(_ characters: [Character], from start: Int) -> (text: String, end: Int, afterSpace: Bool) {
        var index = skippingSpaces(characters, from: start)
        let afterSpace = index > start
        var text = ""
        while index < characters.count {
            let character = characters[index]
            if character.isASCIIDigit {
                let endsAWord = index + 1 >= characters.count
                    || !(characters[index + 1].isLetter || characters[index + 1].isASCIIDigit)
                guard let previous = text.last, previous.isLetter, character == "2" || character == "3", endsAWord else { break }
                text.append(character)
                index += 1
            } else if character.isWhitespace {
                let next = skippingSpaces(characters, from: index)
                if next < characters.count, characters[next].isASCIIDigit { break }
                text.append(" ")
                index = next
            } else if signValue(character) != nil, index + 1 < characters.count, characters[index + 1].isASCIIDigit,
                      index > 0, characters[index - 1].isWhitespace {
                // A sign that starts the next number ("đến -20"), as opposed to one that follows this one ("5-10").
                break
            } else {
                text.append(character)
                index += 1
            }
        }
        return (text.trimmingCharacters(in: .whitespaces), index, afterSpace)
    }
}
