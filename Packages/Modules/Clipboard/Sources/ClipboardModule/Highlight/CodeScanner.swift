import Foundation

/// One pass over a text, byte by byte, turning what `CodeSyntax` describes into tokens.
nonisolated struct CodeScanner {
    /// How many interpolations may open inside each other; a deeper one is left as part of its string, so hostile text
    /// cannot exhaust the stack.
    private static let maxNesting = 24
    private static let maxKeywordLength = 24

    let bytes: UnsafeBufferPointer<UInt8>
    let syntax: CodeSyntax
    /// Never beyond the end of the text, whatever a scanner adds to it: a backslash at the very end is followed by a byte that
    /// does not exist, and skipping that byte must not carry the scan past the end.
    private var index = 0 {
        didSet { if index > bytes.count { index = bytes.count } }
    }
    private var tokens: [CodeToken] = []
    private var nesting = 0
    private var braceDepth = 0

    init(bytes: UnsafeBufferPointer<UInt8>, syntax: CodeSyntax) {
        self.bytes = bytes
        self.syntax = syntax
    }

    mutating func run() -> [CodeToken] {
        scan(closing: nil)
        return tokens
    }

    // MARK: Main loop

    /// Scans code. With `closing`, stops before the byte that closes the interpolation being scanned.
    private mutating func scan(closing: UInt8?) {
        var open = 0
        while index < bytes.count {
            let byte = bytes[index]
            if Self.isSpace(byte) {
                index += 1
            } else if let closing, byte == closing, open == 0 {
                return
            } else if scanPHPTag() || scanComment() || scanString(prefixStart: nil) {
                continue
            } else if startsNumber(byte) {
                scanNumber()
            } else if Self.isWordStart(byte) {
                scanWord()
            } else if scanSpecial(byte) {
                continue
            } else {
                if let closing {
                    if byte == (closing == UInt8(ascii: ")") ? UInt8(ascii: "(") : UInt8(ascii: "{")) { open += 1 }
                    if byte == closing { open -= 1 }
                }
                if byte == UInt8(ascii: "{") { braceDepth += 1 }
                if byte == UInt8(ascii: "}") { braceDepth = max(0, braceDepth - 1) }
                if Self.isPunctuation(byte) { emit(.punctuation, index, index + 1) }
                index += 1
            }
        }
    }

    // MARK: Output

    /// Adds a token for the bytes from `lower` up to `upper`. Both are clamped to the text, so no position computed from a
    /// skipped byte can make an invalid range; an empty one adds nothing.
    private mutating func emit(_ kind: CodeTokenKind, _ lower: Int, _ upper: Int) {
        let upper = min(upper, bytes.count), lower = max(lower, 0)
        guard lower < upper else { return }
        if kind == .punctuation, let last = tokens.last, last.kind == .punctuation, last.range.upperBound == lower {
            tokens[tokens.count - 1] = CodeToken(kind: .punctuation, range: last.range.lowerBound..<upper)
        } else {
            tokens.append(CodeToken(kind: kind, range: lower..<upper))
        }
    }

    private func matches(_ text: StaticString, at position: Int? = nil) -> Bool {
        let start = position ?? index
        guard start + text.utf8CodeUnitCount <= bytes.count else { return false }
        for offset in 0..<text.utf8CodeUnitCount where bytes[start + offset] != text.utf8Start[offset] { return false }
        return true
    }

    private func peek(_ position: Int) -> UInt8? {
        position < bytes.count ? bytes[position] : nil
    }

    // MARK: Comments

    private mutating func scanComment() -> Bool {
        for marker in syntax.lineComments where matches(marker) {
            if syntax.commentNeedsSpace, index > 0, !Self.isSpace(bytes[index - 1]) { continue }
            let start = index
            while index < bytes.count, bytes[index] != UInt8(ascii: "\n"), bytes[index] != UInt8(ascii: "\r") { index += 1 }
            emit(.comment, start, index)
            return true
        }
        guard let block = syntax.blockComment, matches(block.open) else { return false }
        let start = index
        index += block.open.utf8CodeUnitCount
        var open = 1
        while index < bytes.count, open > 0 {
            if matches(block.close) {
                open -= 1
                index += block.close.utf8CodeUnitCount
            } else if syntax.nestedComments, matches(block.open) {
                open += 1
                index += block.open.utf8CodeUnitCount
            } else {
                index += 1
            }
        }
        emit(.comment, start, index)
        return true
    }

    private mutating func scanPHPTag() -> Bool {
        guard syntax.phpTags else { return false }
        for tag: StaticString in ["<?php", "?>"] where matches(tag) {
            emit(.keyword, index, index + tag.utf8CodeUnitCount)
            index += tag.utf8CodeUnitCount
            return true
        }
        return false
    }

    // MARK: Strings

    /// Starts a string at `index`, if one starts there. `prefixStart` is where a word right before it begins (`f` in
    /// `f"…"`), which the string's token includes.
    private mutating func scanString(prefixStart: Int?) -> Bool {
        let start = prefixStart ?? index
        let byte = bytes[index]
        if syntax.hashStrings, scanHashString(start: start) { return true }
        if syntax.verbatimStrings, scanVerbatimString(start: start) { return true }
        switch byte {
        case UInt8(ascii: "\""):
            if syntax.tripleQuotes, matches("\"\"\"") {
                scanTripleQuoted(UInt8(ascii: "\""), start: start)
            } else {
                scanQuoted(UInt8(ascii: "\""), start: start, escapes: syntax.backslashEscapes, interpolates: syntax.interpolatesParentheses)
            }
        case UInt8(ascii: "'"):
            switch syntax.singleQuote {
            case .string(let escapes):
                if syntax.tripleQuotes, case .string = syntax.singleQuote, matches("'''") {
                    scanTripleQuoted(UInt8(ascii: "'"), start: start)
                } else {
                    scanQuoted(UInt8(ascii: "'"), start: start, escapes: escapes, interpolates: false)
                }
            case .character: scanCharacter(start: start)
            case .rustCharacter: scanRustQuote(start: start)
            case .none: return false
            }
        case UInt8(ascii: "`"):
            switch syntax.backtick {
            case .template: scanTemplate(start: start)
            case .raw: scanRawBacktick(start: start)
            case .none: return false
            }
        default:
            return false
        }
        return true
    }

    /// A string on one line: an unclosed one ends with the line, so a stray quote does not swallow the rest of the text.
    /// With `interpolates`, `\(` opens code that is scanned like any other and the string goes on after its `)`.
    private mutating func scanQuoted(_ quote: UInt8, start: Int, escapes: Bool, interpolates: Bool) {
        index += 1
        var pieceStart = start
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") { break }
            if escapes, byte == UInt8(ascii: "\\") {
                if interpolates, peek(index + 1) == UInt8(ascii: "("), nesting < Self.maxNesting {
                    emitString(pieceStart, index)
                    emit(.punctuation, index, index + 2)
                    index += 2
                    interpolate(closing: UInt8(ascii: ")"))
                    pieceStart = index
                    continue
                }
                index = min(index + 2, bytes.count)
                continue
            }
            if byte == quote {
                if syntax.doubledQuotes, peek(index + 1) == quote {
                    index += 2
                    continue
                }
                index += 1
                break
            }
            index += 1
        }
        emitString(pieceStart, min(index, bytes.count))
    }

    /// Scans the code of an interpolation up to its closing byte, emits that byte as punctuation and moves past it.
    private mutating func interpolate(closing: UInt8) {
        nesting += 1
        scan(closing: closing)
        nesting -= 1
        if index < bytes.count {
            emit(.punctuation, index, index + 1)
            index += 1
        }
    }

    private mutating func scanTripleQuoted(_ quote: UInt8, start: Int) {
        index += 3
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "\\") {
                index += 2
            } else if bytes[index] == quote, peek(index + 1) == quote, peek(index + 2) == quote {
                index += 3
                break
            } else {
                index += 1
            }
        }
        emit(.string, start, min(index, bytes.count))
    }

    /// `#"…"#`, `##"…"##`, and with a Rust prefix `r"…"` and `r#"…"#`: nothing inside is escaped.
    private mutating func scanHashString(start: Int) -> Bool {
        let hasRawPrefix = bytes[start..<index].contains { $0 | 0x20 == UInt8(ascii: "r") }
        var hashes = 0
        while peek(index + hashes) == UInt8(ascii: "#") { hashes += 1 }
        guard peek(index + hashes) == UInt8(ascii: "\""), hashes > 0 || hasRawPrefix else {
            // A run of `#` that opens no string is one token. Counting it again from each of its bytes would take time that grows
            // with the square of its length.
            guard hashes > 1, start == index else { return false }
            emit(.punctuation, index, index + hashes)
            index += hashes
            return true
        }
        index += hashes + 1
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "\"") {
                var count = 0
                while count < hashes, peek(index + 1 + count) == UInt8(ascii: "#") { count += 1 }
                if count == hashes {
                    index += 1 + hashes
                    break
                }
            }
            index += 1
        }
        emit(.string, start, min(index, bytes.count))
        return true
    }

    /// C#'s `@"…"` and `$@"…"`, where a doubled quote stands for one.
    private mutating func scanVerbatimString(start: Int) -> Bool {
        var quote = index
        if bytes[quote] == UInt8(ascii: "$"), peek(quote + 1) == UInt8(ascii: "@") { quote += 1 }
        guard bytes[quote] == UInt8(ascii: "@"), peek(quote + 1) == UInt8(ascii: "\"") else { return false }
        index = quote + 2
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "\"") {
                if peek(index + 1) == UInt8(ascii: "\"") {
                    index += 2
                    continue
                }
                index += 1
                break
            }
            index += 1
        }
        emit(.string, start, min(index, bytes.count))
        return true
    }

    /// `'x'`, `'\n'`, `'A'`; a quote that closes nothing close by is punctuation.
    private mutating func scanCharacter(start: Int) {
        var end = index + 1
        if peek(end) == UInt8(ascii: "\\") { end += 2 } else { end = skipCharacter(at: end) }
        while end < bytes.count, bytes[end] != UInt8(ascii: "'"), bytes[end] != UInt8(ascii: "\n"), end - index < 12 { end += 1 }
        if peek(end) == UInt8(ascii: "'") {
            emit(.string, start, end + 1)
            index = end + 1
        } else {
            emit(.punctuation, index, index + 1)
            index += 1
        }
    }

    /// A Rust `'x'` or `'\n'` is a character; `'a` and `'static` are lifetimes and stay plain.
    private mutating func scanRustQuote(start: Int) {
        var end = index + 1
        if peek(end) == UInt8(ascii: "\\") {
            end += 2
            while end < bytes.count, bytes[end] != UInt8(ascii: "'"), bytes[end] != UInt8(ascii: "\n"), end - index < 14 { end += 1 }
        } else {
            end = skipCharacter(at: end)
        }
        if peek(end) == UInt8(ascii: "'") {
            emit(.string, start, end + 1)
            index = end + 1
            return
        }
        index += 1
        while index < bytes.count, Self.isWordByte(bytes[index]) { index += 1 }
    }

    /// The offset after the character that starts at `position`, whose UTF-8 form may take several bytes.
    private func skipCharacter(at position: Int) -> Int {
        guard position < bytes.count else { return position }
        var end = position + 1
        while end < bytes.count, bytes[end] & 0xC0 == 0x80 { end += 1 }
        return end
    }

    private mutating func scanRawBacktick(start: Int) {
        index += 1
        while index < bytes.count, bytes[index] != UInt8(ascii: "`") { index += 1 }
        index = min(index + 1, bytes.count)
        emit(.string, start, index)
    }

    /// JavaScript's backtick string, which spans lines and runs `${…}` as code, nested as deep as the text goes.
    private mutating func scanTemplate(start: Int) {
        index += 1
        var pieceStart = start
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\\") {
                index = min(index + 2, bytes.count)
            } else if byte == UInt8(ascii: "`") {
                index += 1
                break
            } else if byte == UInt8(ascii: "$"), peek(index + 1) == UInt8(ascii: "{"), nesting < Self.maxNesting {
                emitString(pieceStart, index)
                emit(.punctuation, index, index + 2)
                index += 2
                interpolate(closing: UInt8(ascii: "}"))
                pieceStart = index
            } else {
                index += 1
            }
        }
        emitString(pieceStart, min(index, bytes.count))
    }

    /// A string; or a key, when the language marks `"key": …` as one.
    private mutating func emitString(_ lower: Int, _ upper: Int) {
        if syntax.highlightsKeys, isFollowedByColon(at: upper) {
            emit(.keyword, lower, upper)
        } else {
            emit(.string, lower, upper)
        }
    }

    private func isFollowedByColon(at position: Int) -> Bool {
        var next = position
        while next < bytes.count, bytes[next] == UInt8(ascii: " ") || bytes[next] == UInt8(ascii: "\t") { next += 1 }
        return peek(next) == UInt8(ascii: ":")
    }

    // MARK: Numbers and words

    private func startsNumber(_ byte: UInt8) -> Bool {
        if Self.isDigit(byte) { return true }
        let next = peek(index + 1)
        // After a name, a closing bracket or a dot, "." or "-" is an operator: `t.0`, `a[1].5`, `1..5`.
        let followsOperand = index > 0 && (Self.isWordByte(bytes[index - 1]) || ")].".utf8.contains(bytes[index - 1]))
        if byte == UInt8(ascii: "."), let next, Self.isDigit(next) { return !followsOperand }
        if byte == UInt8(ascii: "-"), syntax.negativeNumbers, let next, Self.isDigit(next) { return !followsOperand }
        return false
    }

    /// Digits with `_`, a fraction, an exponent, a base prefix, and the letters that follow (a suffix such as `u32` or a
    /// unit such as `px`).
    private mutating func scanNumber() {
        let start = index
        if bytes[index] == UInt8(ascii: "-") { index += 1 }
        if bytes[index] == UInt8(ascii: "0"), let marker = peek(index + 1), [0x78, 0x62, 0x6F].contains(marker | 0x20) {
            index += 2
            while index < bytes.count, Self.isWordByte(bytes[index]) { index += 1 }
            emit(.number, start, index)
            return
        }
        skipDigits()
        if peek(index) == UInt8(ascii: "."), let next = peek(index + 1), Self.isDigit(next) {
            index += 1
            skipDigits()
        }
        if let marker = peek(index), marker | 0x20 == UInt8(ascii: "e") {
            let hasSign = peek(index + 1).map { $0 == UInt8(ascii: "+") || $0 == UInt8(ascii: "-") } ?? false
            if peek(index + (hasSign ? 2 : 1)).map(Self.isDigit) == true {
                index += hasSign ? 2 : 1
                skipDigits()
            }
        }
        while index < bytes.count, Self.isWordByte(bytes[index]) { index += 1 }
        emit(.number, start, index)
    }

    private mutating func skipDigits() {
        while index < bytes.count, Self.isDigit(bytes[index]) || bytes[index] == UInt8(ascii: "_") { index += 1 }
    }

    private mutating func scanWord() {
        let start = index
        index += 1
        while index < bytes.count {
            let byte = bytes[index]
            if Self.isWordByte(byte) {
                index += 1
            } else if syntax.wordExtras.contains(byte), let next = peek(index + 1), Self.isWordByte(next) {
                index += 2
            } else {
                break
            }
        }
        let quote = peek(index)
        if !syntax.stringPrefixes.isEmpty, quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'") || (syntax.hashStrings && quote == UInt8(ascii: "#")),
           index - start <= 2, isStringPrefix(start..<index), scanString(prefixStart: start) {
            return
        }
        if syntax.highlightsKeys, isKey(start..<index) {
            emit(.keyword, start, index)
        } else if isKeyword(start..<index) {
            emit(.keyword, start, index)
        }
    }

    private func isStringPrefix(_ range: Range<Int>) -> Bool {
        syntax.stringPrefixes.contains(String(decoding: bytes[range].map { $0 | 0x20 }, as: UTF8.self))
    }

    private func isKeyword(_ range: Range<Int>) -> Bool {
        guard range.count <= Self.maxKeywordLength, !syntax.keywords.isEmpty else { return false }
        let word = String(decoding: bytes[range], as: UTF8.self)
        return syntax.keywords.contains(syntax.ignoresCase ? word.lowercased() : word)
    }

    /// YAML: a word right before ": " or the end of the line. CSS: a word before a colon inside braces.
    private func isKey(_ range: Range<Int>) -> Bool {
        if syntax.hexColors { return braceDepth > 0 && isFollowedByColon(at: range.upperBound) }
        guard peek(range.upperBound) == UInt8(ascii: ":") else { return false }
        guard let after = peek(range.upperBound + 1) else { return true }
        return after == UInt8(ascii: " ") || after == UInt8(ascii: "\n") || after == UInt8(ascii: "\r") || after == UInt8(ascii: "\t")
    }

    // MARK: Specials

    /// `$name`, `@word`, `#include` and `#fff`, which each need more than the byte itself.
    private mutating func scanSpecial(_ byte: UInt8) -> Bool {
        let next = peek(index + 1)
        switch byte {
        case UInt8(ascii: "$") where syntax.variables:
            guard let next else { return false }
            if Self.isWordStart(next) {
                index += 1
                while index < bytes.count, Self.isWordByte(bytes[index]) { index += 1 }
                return true
            }
            if Self.isDigit(next) || "@?!#*$-".utf8.contains(next) {
                index += 2
                return true
            }
            return false
        case UInt8(ascii: "@") where syntax.atKeywords:
            guard let next, Self.isWordStart(next) else { return false }
            let start = index
            index += 1
            while index < bytes.count, Self.isWordByte(bytes[index]) || (syntax.wordExtras.contains(bytes[index])) { index += 1 }
            emit(.keyword, start, index)
            return true
        case UInt8(ascii: "#") where syntax.preprocessor:
            guard let next, next | 0x20 >= UInt8(ascii: "a"), next | 0x20 <= UInt8(ascii: "z"), isFirstOnLine(index) else { return false }
            let start = index
            index += 1
            while index < bytes.count, Self.isWordByte(bytes[index]) { index += 1 }
            emit(.keyword, start, index)
            return true
        case UInt8(ascii: "#") where syntax.hexColors && braceDepth > 0:
            var end = index + 1
            while end < bytes.count, Self.isHexDigit(bytes[end]) { end += 1 }
            let digits = end - index - 1
            guard [3, 4, 6, 8].contains(digits), !(peek(end).map(Self.isWordByte) ?? false) else { return false }
            emit(.number, index, end)
            index = end
            return true
        default:
            return false
        }
    }

    private func isFirstOnLine(_ position: Int) -> Bool {
        var before = position
        while before > 0, bytes[before - 1] == UInt8(ascii: " ") || bytes[before - 1] == UInt8(ascii: "\t") { before -= 1 }
        return before == 0 || bytes[before - 1] == UInt8(ascii: "\n") || bytes[before - 1] == UInt8(ascii: "\r")
    }

    // MARK: Byte classes

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || (byte >= 0x09 && byte <= 0x0D)
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }

    private static func isHexDigit(_ byte: UInt8) -> Bool {
        isDigit(byte) || (byte | 0x20 >= UInt8(ascii: "a") && byte | 0x20 <= UInt8(ascii: "f"))
    }

    /// Letters, `_`, `$` where it is a name, and any non-ASCII byte, so a multi-byte character is never split.
    private static func isWordStart(_ byte: UInt8) -> Bool {
        (byte | 0x20 >= UInt8(ascii: "a") && byte | 0x20 <= UInt8(ascii: "z")) || byte == UInt8(ascii: "_") || byte >= 0x80
    }

    private static func isWordByte(_ byte: UInt8) -> Bool {
        isWordStart(byte) || isDigit(byte)
    }

    private static func isPunctuation(_ byte: UInt8) -> Bool {
        byte > 0x20 && byte < 0x7F && !isWordByte(byte)
    }
}
