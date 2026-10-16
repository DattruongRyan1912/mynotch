import Foundation

/// What a page says is kept only after it has been made plain: a page can put anything in its title, and the title is drawn in MyNotch's
/// own cards. Entities are decoded first and characters stripped after, so `&#7;` cannot slip a control character past the strip.
nonisolated enum ClipboardLinkText {
    static let titleLimit = 200

    /// The words of a title or an attribute, plain: entities decoded (an unknown or impossible one is dropped, a lone `&` stays), line
    /// breaks and runs of white space made one space, control characters, line and paragraph separators, zero-width characters and
    /// the characters that reverse the direction of text removed, trimmed, and cut at `titleLimit` characters. nil when nothing is left.
    static func title(from raw: String) -> String? {
        let plain = plainText(raw)
        guard !plain.isEmpty else { return nil }
        return String(plain.prefix(titleLimit))
    }

    static func plainText(_ raw: String) -> String {
        var result = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in decodingEntities(raw).unicodeScalars {
            // Line breaks, tabs, no-break and ideographic spaces and the line and paragraph separators are all white space.
            if scalar.properties.isWhitespace {
                pendingSpace = !result.isEmpty
                continue
            }
            guard !isStripped(scalar) else { continue }
            if pendingSpace { result.append(" ") }
            pendingSpace = false
            result.append(scalar)
        }
        return String(result)
    }

    /// Control characters (C0, DEL and C1), the zero-width and invisible characters that hide text, the bidirectional marks, embeddings,
    /// overrides and isolates, and U+FFFD (which is only what a failed decoding leaves). Joiners stay: emoji sequences need them.
    private static func isStripped(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200B, 0x200E, 0x200F, 0x2060, 0x061C, 0xFEFF, 0xFFFD, 0x00AD: true
        case 0x202A...0x202E, 0x2066...0x2069: true
        default: scalar.properties.generalCategory == .control
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
