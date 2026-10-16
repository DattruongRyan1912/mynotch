import Foundation

/// What a page says is kept only after it has been made plain: a page can put anything in its title, and the title is drawn in MyNotch's
/// own cards. Entities are decoded first and characters stripped after, so `&#7;` cannot slip a control character past the strip.
nonisolated enum ClipboardLinkText {
    static let titleLimit = 200
    /// A title has at most this many Unicode scalars, cut before the characters are counted: a character (a grapheme cluster) can hold any
    /// number of combining marks, so 200 characters alone bound nothing.
    static let titleScalarLimit = 400
    /// Combining marks after one letter beyond this many are dropped (Vietnamese needs two, a stack of a hundred is not text).
    static let marksPerLetter = 4

    /// The words of a title or an attribute, plain: entities decoded (an unknown or impossible one is dropped, a lone `&` stays), line
    /// breaks and runs of white space made one space, control characters, line and paragraph separators, invisible and zero-width
    /// characters and the ones that reverse the direction of text removed, a stack of combining marks cut short, trimmed, and cut at
    /// `titleScalarLimit` Unicode scalars and then at `titleLimit` characters. nil when nothing is left.
    static func title(from raw: String) -> String? {
        let plain = plainText(raw)
        guard !plain.isEmpty else { return nil }
        return String(String(plain.unicodeScalars.prefix(titleScalarLimit)).prefix(titleLimit))
    }

    static func plainText(_ raw: String) -> String {
        var result = String.UnicodeScalarView()
        var pendingSpace = false
        var marks = 0
        for scalar in decodingEntities(raw).unicodeScalars {
            // Line breaks, tabs, no-break and ideographic spaces and the line and paragraph separators are all white space.
            if scalar.properties.isWhitespace {
                pendingSpace = !result.isEmpty
                marks = 0
                continue
            }
            guard !isStripped(scalar) else { continue }
            if isMark(scalar) {
                marks += 1
                guard marks <= marksPerLetter else { continue }
            } else {
                marks = 0
            }
            if pendingSpace { result.append(" ") }
            pendingSpace = false
            result.append(scalar)
        }
        return String(result)
    }

    /// What is not shown, or not shown as text, and is therefore a way to hide words: control characters (C0, DEL and C1), every
    /// default-ignorable scalar (zero-width and joiner-like characters, soft hyphen, Hangul fillers, combining grapheme joiner, variation
    /// selectors, tag characters), the other format characters (the bidirectional marks, embeddings, overrides and isolates, the invisible
    /// operators), the object replacement character and U+FFFD (which is only what a failed decoding leaves). Four stay because emoji need
    /// them: the joiner and non-joiner (U+200D, U+200C) and the text and emoji presentation selectors (U+FE0E, U+FE0F). That costs the
    /// England, Scotland and Wales flags, which are spelled with tag characters.
    private static func isStripped(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200C, 0x200D, 0xFE0E, 0xFE0F: return false
        case 0xFFFC, 0xFFFD: return true
        default:
            let properties = scalar.properties
            return properties.generalCategory == .control || properties.generalCategory == .format || properties.isDefaultIgnorableCodePoint
        }
    }

    private static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: true
        default: false
        }
    }

    // MARK: Entities

    /// The ones a title uses: the Latin-1 letters and signs, and the punctuation, arrows and symbols of ordinary pages. HTML has about two
    /// thousand; the rest are dropped, which is why this is a table and not a guess.
    private static let named: [String: String] = {
        var table: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "trade": "™", "hellip": "…", "mdash": "—", "ndash": "–",
            "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "sbquo": "‚", "bdquo": "„", "bull": "•", "euro": "€", "larr": "←",
            "rarr": "→", "uarr": "↑", "darr": "↓", "hearts": "♥", "check": "✓", "star": "☆", "oelig": "œ", "OElig": "Œ",
        ]
        // U+00A0 to U+00FF, in the order HTML names them.
        let latin1 = [
            "nbsp", "iexcl", "cent", "pound", "curren", "yen", "brvbar", "sect", "uml", "copy", "ordf", "laquo", "not", "shy", "reg", "macr",
            "deg", "plusmn", "sup2", "sup3", "acute", "micro", "para", "middot", "cedil", "sup1", "ordm", "raquo", "frac14", "frac12",
            "frac34", "iquest", "Agrave", "Aacute", "Acirc", "Atilde", "Auml", "Aring", "AElig", "Ccedil", "Egrave", "Eacute", "Ecirc",
            "Euml", "Igrave", "Iacute", "Icirc", "Iuml", "ETH", "Ntilde", "Ograve", "Oacute", "Ocirc", "Otilde", "Ouml", "times", "Oslash",
            "Ugrave", "Uacute", "Ucirc", "Uuml", "Yacute", "THORN", "szlig", "agrave", "aacute", "acirc", "atilde", "auml", "aring", "aelig",
            "ccedil", "egrave", "eacute", "ecirc", "euml", "igrave", "iacute", "icirc", "iuml", "eth", "ntilde", "ograve", "oacute", "ocirc",
            "otilde", "ouml", "divide", "oslash", "ugrave", "uacute", "ucirc", "uuml", "yacute", "thorn", "yuml",
        ]
        for (offset, name) in latin1.enumerated() {
            table[name] = String(Character(Unicode.Scalar(UInt32(0xA0 + offset))!))
        }
        return table
    }()

    /// `&name;`, `&#123;` and `&#x1F600;`, once each (`&amp;lt;` is `&lt;`, not `<`). A number that is not a character, or is a control
    /// character, and a name that is not in the table are removed; an `&` that starts none of these stays.
    static func decodingEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character == "&", let end = text[index...].prefix(40).firstIndex(of: ";"),
                  let decoded = decode(String(text[text.index(after: index)..<end])) else {
                result.append(character)
                index = text.index(after: index)
                continue
            }
            result += decoded
            index = text.index(after: end)
        }
        return result
    }

    /// The text between `&` and `;`: nil when it is not an entity at all, "" when it is one that is dropped.
    private static func decode(_ name: String) -> String? {
        guard let first = name.first else { return nil }
        if first == "#" {
            let digits = name.dropFirst()
            let isHex = digits.first == "x" || digits.first == "X"
            let body = isHex ? digits.dropFirst() : digits
            guard !body.isEmpty, body.allSatisfy({ isHex ? $0.isHexDigit : $0.isASCII && $0.isNumber }) else { return nil }
            // A number too big for a character is as impossible as a surrogate. A control character it names is decoded like any other
            // and stripped after, with the ones the page wrote itself.
            guard let value = UInt32(body, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(value) else { return "" }
            return String(Character(scalar))
        }
        guard first.isLetter, first.isASCII, name.count <= 32, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return named[name] ?? ""
    }
}
