import Foundation

/// A number with a unit, such as "5 ft 11 in" (as 5,92 ft) or "72 °F".
struct UnitQuantity: Equatable {
    var value: Double
    var unit: MeasureUnit
    /// Safe to take from running text: it did not rest on a one-letter unit, a quote mark or "in".
    var isUnambiguous: Bool
}

/// Reads a whole text as a quantity: sign, then a number and its unit, and for lengths, masses and volumes more such
/// pairs of smaller units ("5 ft 11 in", "5'11\"", "1 lb 8 oz"). A bare number after feet counts as inches.
enum UnitQuantityParser {
    static func parse(_ text: String) -> UnitQuantity? {
        let characters = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
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
            let (unitText, afterUnit) = readUnit(characters, from: afterNumber)
            var unit: MeasureUnit?
            if !unitText.isEmpty {
                guard let match = UnitCatalog.match(unitText) else { return nil }
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
    /// belongs to it ("m2", "ft3"), unless a letter follows ("ft2in" is 2 inches).
    private static func readUnit(_ characters: [Character], from start: Int) -> (text: String, end: Int) {
        var index = skippingSpaces(characters, from: start)
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
            } else {
                text.append(character)
                index += 1
            }
        }
        return (text.trimmingCharacters(in: .whitespaces), index)
    }
}
