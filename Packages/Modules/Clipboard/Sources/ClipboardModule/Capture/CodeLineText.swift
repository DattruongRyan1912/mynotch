import Foundation

/// Small checks on one line of text that tell prose from code: where its words are, and whether it has letters that only
/// prose has.
nonisolated enum CodeLineText {
    /// Words that join two others in code (`for x in y`, `a and b`, `new Foo`), so two bare words around them are not a
    /// sentence.
    private static let connectors: Set<String> = [
        "in", "of", "is", "as", "and", "or", "not", "new", "await", "async", "typeof", "instanceof", "extends", "implements", "if",
        "else", "for", "where", "from", "import", "then", "do", "let", "var", "const", "static", "final", "mut", "ref",
    ]

    /// Quoted text replaced by an empty pair of the same quotes. A quote that is never closed stays as it is, since it is
    /// an apostrophe more often than not ("it's").
    static func strippingStrings(_ text: String) -> String {
        let bytes = Array(text.utf8)
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            let isQuote = byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") || byte == UInt8(ascii: "`")
            if isQuote, let close = closingQuote(bytes, after: index) {
                result += [byte, byte]
                index = close + 1
            } else {
                result.append(byte)
                index += 1
            }
        }
        return String(decoding: result, as: UTF8.self)
    }

    private static func closingQuote(_ bytes: [UInt8], after start: Int) -> Int? {
        var index = start + 1
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "\\") {
                index += 2
            } else if bytes[index] == bytes[start] {
                return index
            } else {
                index += 1
            }
        }
        return nil
    }

    /// Whether the line has a letter beyond ASCII (a Vietnamese vowel with its marks, for one) outside quotes and comments.
    /// Code keeps such letters in its strings and comments; a line that has them elsewhere is a sentence.
    static func hasProseLetters(_ text: String) -> Bool {
        guard text.utf8.contains(where: { $0 >= 0x80 }) else { return false }
        var previous: Unicode.Scalar = " "
        var scalars = strippingStrings(text).unicodeScalars.makeIterator()
        var next = scalars.next()
        while let scalar = next {
            let following = scalars.next()
            if scalar == "/", following == "/" || following == "*" { return false }
            if scalar == "#", previous == " " { return false }
            if scalar.value >= 0x80, scalar.properties.isAlphabetic { return true }
            previous = scalar
            next = following
        }
        return false
    }

    /// Two plain words side by side, like "to base": code puts an operator, a bracket or a keyword between names. A word
    /// ending a list item ("os, sys") starts over.
    static func hasAdjacentWords(_ text: String) -> Bool {
        var previousWasWord = false
        for token in strippingStrings(text).split(whereSeparator: \.isWhitespace) {
            let word = token.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!?()"))
            let isWord = !word.isEmpty && word.allSatisfy { $0.isASCII && $0.isLetter } && !connectors.contains(word.lowercased())
            if isWord, previousWasWord { return true }
            previousWasWord = isWord && !(token.hasSuffix(",") || token.hasSuffix(";"))
        }
        return false
    }

    /// A matched pair of brackets, even an empty one: `()`, `{ x }`, `[1]`.
    static func hasBracketPair(_ text: String) -> Bool {
        var open: [UInt8] = []
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "("), UInt8(ascii: "{"), UInt8(ascii: "["): open.append(byte)
            case UInt8(ascii: ")"): if open.last == UInt8(ascii: "(") { return true }
            case UInt8(ascii: "}"): if open.last == UInt8(ascii: "{") { return true }
            case UInt8(ascii: "]"): if open.last == UInt8(ascii: "[") { return true }
            default: break
            }
        }
        return false
    }
}
