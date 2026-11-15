import Foundation

/// Fast, zero-dependency TOML parser adhering to the TOML v1.0 specification.
nonisolated public enum TOMLParser {
    public static func parse(_ source: String) throws -> TOMLTable {
        var parser = Parser(source: source)
        return try parser.parseDocument()
    }

    public static func parseToDictionary(_ source: String) throws -> [String: Any] {
        let table = try parse(source)
        return TOMLValue.toDictionary(table)
    }
}

nonisolated private struct Parser: Sendable {
    private let chars: [Character]
    private var index: Int = 0
    private var line: Int = 1
    private var col: Int = 1

    init(source: String) {
        // Normalize CRLF to LF to avoid Swift extended grapheme cluster combining "\r\n" into a single Character.
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        self.chars = Array(normalized)
    }

    private var isEOF: Bool { index >= chars.count }
    private var peek: Character? { isEOF ? nil : chars[index] }

    private mutating func advance() -> Character? {
        guard !isEOF else { return nil }
        let c = chars[index]
        index += 1
        if c == "\n" {
            line += 1
            col = 1
        } else {
            col += 1
        }
        return c
    }

    private func error(_ kind: TOMLError.Kind) -> TOMLError {
        TOMLError(line: line, column: col, kind: kind)
    }

    private mutating func skipWhitespace(includeNewlines: Bool = false) {
        while !isEOF {
            guard let c = peek else { break }
            if c == " " || c == "\t" {
                _ = advance()
            } else if c == "\n" {
                if includeNewlines {
                    _ = advance()
                } else {
                    break
                }
            } else if c == "#" {
                // Comment until end of line
                while !isEOF && peek != "\n" {
                    _ = advance()
                }
                if includeNewlines && peek == "\n" {
                    _ = advance()
                }
            } else {
                break
            }
        }
    }

    mutating func parseDocument() throws -> TOMLTable {
        var root: TOMLTable = [:]
        var currentSection: [String] = []
        var definedSections = Set<String>()

        while !isEOF {
            skipWhitespace(includeNewlines: false)
            if isEOF { break }
            guard let c = peek else { break }

            if c == "\n" {
                _ = advance()
                continue
            }

            if c == "[" {
                _ = advance()
                if peek == "[" {
                    // Array of tables [[table]]
                    _ = advance()
                    let path = try parseKeyPath()
                    skipWhitespace()
                    guard peek == "]" else { throw error(.unexpectedCharacter(peek ?? " ")) }
                    _ = advance()
                    guard peek == "]" else { throw error(.unexpectedCharacter(peek ?? " ")) }
                    _ = advance()
                    currentSection = path
                    let sectionKey = path.joined(separator: ".")
                    // Reset defined sub-sections under this array of tables so repeated elements can define their own sub-tables
                    definedSections = definedSections.filter { $0 != sectionKey && !$0.hasPrefix(sectionKey + ".") }
                    try ensureArrayOfTables(in: &root, path: path)
                } else {
                    // Standard section [table]
                    let path = try parseKeyPath()
                    skipWhitespace()
                    guard peek == "]" else { throw error(.unexpectedCharacter(peek ?? " ")) }
                    _ = advance()
                    let sectionKey = path.joined(separator: ".")
                    if definedSections.contains(sectionKey) {
                        throw error(.conflictingTableDefinition(sectionKey))
                    }
                    definedSections.insert(sectionKey)
                    currentSection = path
                    try ensureTable(in: &root, path: path)
                }
                try expectEndOfLine()
            } else {
                // Key-value pair
                let keyPath = try parseKeyPath()
                skipWhitespace()
                guard peek == "=" else { throw error(.expectedEquals) }
                _ = advance()
                skipWhitespace()
                let value = try parseValue()
                skipWhitespace()
                try expectEndOfLine()

                // Insert into root or current section
                let fullPath = currentSection + keyPath
                try insert(value: value, at: fullPath, in: &root)
            }
        }

        return root
    }

    private mutating func expectEndOfLine() throws {
        skipWhitespace()
        if isEOF { return }
        guard let c = peek else { return }
        if c == "\n" {
            _ = advance()
        } else if c == "#" {
            while !isEOF && peek != "\n" { _ = advance() }
            if peek == "\n" { _ = advance() }
        } else {
            throw error(.trailingContent)
        }
    }

    // MARK: - Key Parsing

    private mutating func parseKeyPath() throws -> [String] {
        var path: [String] = []
        while true {
            skipWhitespace()
            let key = try parseSingleKey()
            path.append(key)
            skipWhitespace()
            if peek == "." {
                _ = advance()
            } else {
                break
            }
        }
        guard !path.isEmpty else { throw error(.invalidKey) }
        return path
    }

    private mutating func parseSingleKey() throws -> String {
        guard let c = peek else { throw error(.invalidKey) }
        if c == "\"" {
            return try parseBasicString()
        } else if c == "'" {
            return try parseLiteralString()
        } else if isBareKeyChar(c) {
            var s = ""
            while let ch = peek, isBareKeyChar(ch) {
                s.append(ch)
                _ = advance()
            }
            return s
        } else {
            throw error(.invalidKey)
        }
    }

    private func isBareKeyChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "-"
    }

    // MARK: - Value Parsing

    private mutating func parseValue() throws -> TOMLValue {
        guard let c = peek else { throw error(.unexpectedCharacter(" ")) }

        if c == "\"" {
            if hasPrefix("\"\"\"") {
                return .string(try parseMultilineBasicString())
            }
            return .string(try parseBasicString())
        } else if c == "'" {
            if hasPrefix("'''") {
                return .string(try parseMultilineLiteralString())
            }
            return .string(try parseLiteralString())
        } else if c == "t" || c == "f" {
            if hasWord("true") {
                advanceCount(4)
                return .boolean(true)
            } else if hasWord("false") {
                advanceCount(5)
                return .boolean(false)
            }
        } else if c == "[" {
            return try parseArray()
        } else if c == "{" {
            return try parseInlineTable()
        }

        // Special float checks: inf, nan
        if (c == "+" || c == "-" || c == "i" || c == "n") {
            if let special = try parseSpecialFloat() {
                return special
            }
        }

        // Number (integer / float)
        if c == "+" || c == "-" || c.isNumber {
            return try parseNumber()
        }

        throw error(.unexpectedCharacter(c))
    }

    // MARK: - Strings

    private func hasPrefix(_ str: String) -> Bool {
        let count = str.count
        guard index + count <= chars.count else { return false }
        let slice = chars[index..<(index + count)]
        return String(slice) == str
    }

    private func hasWord(_ word: String) -> Bool {
        guard hasPrefix(word) else { return false }
        let after = index + word.count
        if after < chars.count {
            let nextChar = chars[after]
            if isBareKeyChar(nextChar) { return false }
        }
        return true
    }

    private mutating func advanceCount(_ count: Int) {
        for _ in 0..<count { _ = advance() }
    }

    private mutating func parseBasicString() throws -> String {
        _ = advance() // skip leading "
        var res = ""
        while !isEOF {
            guard let c = advance() else { throw error(.unterminatedString) }
            if c == "\"" { return res }
            if c == "\n" { throw error(.unterminatedString) }
            if c == "\\" {
                guard let esc = advance() else { throw error(.unterminatedString) }
                switch esc {
                case "\"": res.append("\"")
                case "\\": res.append("\\")
                case "b": res.append("\u{0008}")
                case "t": res.append("\t")
                case "n": res.append("\n")
                case "f": res.append("\u{000C}")
                case "r": res.append("\r")
                case "u":
                    res.append(try parseHexEscape(length: 4))
                case "U":
                    res.append(try parseHexEscape(length: 8))
                default:
                    throw error(.invalidEscape(String(esc)))
                }
            } else {
                res.append(c)
            }
        }
        throw error(.unterminatedString)
    }

    private mutating func parseHexEscape(length: Int) throws -> Character {
        var hex = ""
        for _ in 0..<length {
            guard let c = advance(), c.isHexDigit else { throw error(.invalidEscape(hex)) }
            hex.append(c)
        }
        guard let codePoint = UInt32(hex, radix: 16),
              let scalar = UnicodeScalar(codePoint) else {
            throw error(.invalidEscape(hex))
        }
        return Character(scalar)
    }

    private mutating func parseMultilineBasicString() throws -> String {
        advanceCount(3) // skip """
        if peek == "\n" { _ = advance() } // trim first newline
        var res = ""
        while !isEOF {
            if hasPrefix("\"\"\"") {
                advanceCount(3)
                return res
            }
            guard let c = advance() else { throw error(.unterminatedString) }
            if c == "\\" {
                guard let next = peek else { throw error(.unterminatedString) }
                if next == "\n" {
                    _ = advance()
                    while !isEOF, let ws = peek, ws == " " || ws == "\t" || ws == "\n" {
                        _ = advance()
                    }
                } else {
                    _ = advance()
                    switch next {
                    case "\"": res.append("\"")
                    case "\\": res.append("\\")
                    case "b": res.append("\u{0008}")
                    case "t": res.append("\t")
                    case "n": res.append("\n")
                    case "f": res.append("\u{000C}")
                    case "r": res.append("\r")
                    case "u": res.append(try parseHexEscape(length: 4))
                    case "U": res.append(try parseHexEscape(length: 8))
                    default: throw error(.invalidEscape(String(next)))
                    }
                }
            } else {
                res.append(c)
            }
        }
        throw error(.unterminatedString)
    }

    private mutating func parseLiteralString() throws -> String {
        _ = advance() // skip '
        var res = ""
        while !isEOF {
            guard let c = advance() else { throw error(.unterminatedString) }
            if c == "'" { return res }
            if c == "\n" { throw error(.unterminatedString) }
            res.append(c)
        }
        throw error(.unterminatedString)
    }

    private mutating func parseMultilineLiteralString() throws -> String {
        advanceCount(3) // skip '''
        if peek == "\n" { _ = advance() }
        var res = ""
        while !isEOF {
            if hasPrefix("'''") {
                advanceCount(3)
                return res
            }
            guard let c = advance() else { throw error(.unterminatedString) }
            res.append(c)
        }
        throw error(.unterminatedString)
    }

    // MARK: - Numbers

    private mutating func parseSpecialFloat() throws -> TOMLValue? {
        let savedIndex = index
        let savedCol = col
        var sign = ""
        if peek == "+" || peek == "-" {
            sign.append(advance()!)
        }

        if hasWord("inf") {
            advanceCount(3)
            return .float(sign == "-" ? -Double.infinity : Double.infinity)
        } else if hasWord("nan") {
            advanceCount(3)
            return .float(Double.nan)
        }

        index = savedIndex
        col = savedCol
        return nil
    }

    private mutating func parseNumber() throws -> TOMLValue {
        var raw = ""
        if peek == "+" || peek == "-" {
            raw.append(advance()!)
        }

        // Radix ints: 0x, 0o, 0b (must not have leading sign)
        if raw.isEmpty && peek == "0" {
            let nextIndex = index + 1
            if nextIndex < chars.count {
                let radixChar = chars[nextIndex]
                if radixChar == "x" || radixChar == "o" || radixChar == "b" {
                    _ = advance() // 0
                    _ = advance() // radixChar
                    var digits = ""
                    var lastWasUnderscore = false
                    guard let firstC = peek, firstC.isHexDigit else { throw error(.invalidNumber) }

                    while let c = peek {
                        if c.isHexDigit {
                            digits.append(c)
                            lastWasUnderscore = false
                            _ = advance()
                        } else if c == "_" {
                            if lastWasUnderscore { throw error(.invalidNumber) }
                            lastWasUnderscore = true
                            _ = advance()
                        } else {
                            break
                        }
                    }
                    if lastWasUnderscore || digits.isEmpty { throw error(.invalidNumber) }
                    let radix: Int = radixChar == "x" ? 16 : (radixChar == "o" ? 8 : 2)
                    guard let val = Int64(digits, radix: radix) else { throw error(.invalidNumber) }
                    return .integer(val)
                }
            }
        }

        var isFloat = false
        var hasDigits = false
        var lastWasUnderscore = false

        while let c = peek {
            if c.isNumber {
                raw.append(c)
                hasDigits = true
                lastWasUnderscore = false
                _ = advance()
            } else if c == "_" {
                if !hasDigits || lastWasUnderscore { throw error(.invalidNumber) }
                lastWasUnderscore = true
                _ = advance()
            } else if c == "." {
                if lastWasUnderscore || isFloat { throw error(.invalidNumber) }
                isFloat = true
                raw.append(c)
                lastWasUnderscore = false
                _ = advance()
                // Must have digit immediately after dot
                guard let next = peek, next.isNumber else { throw error(.invalidNumber) }
            } else if c == "e" || c == "E" {
                if lastWasUnderscore { throw error(.invalidNumber) }
                isFloat = true
                raw.append(c)
                lastWasUnderscore = false
                _ = advance()
                if peek == "+" || peek == "-" {
                    raw.append(advance()!)
                }
                guard let next = peek, next.isNumber else { throw error(.invalidNumber) }
            } else {
                break
            }
        }

        if lastWasUnderscore || !hasDigits { throw error(.invalidNumber) }

        // Decimal integer leading zero check (e.g. 0123 is invalid in TOML)
        let bare = raw.hasPrefix("+") || raw.hasPrefix("-") ? String(raw.dropFirst()) : raw
        if !isFloat {
            if bare.count > 1 && bare.hasPrefix("0") {
                throw error(.invalidNumber)
            }
            guard let i = Int64(raw) else { throw error(.invalidNumber) }
            return .integer(i)
        } else {
            let integerPart = bare.split(separator: ".", omittingEmptySubsequences: false)[0]
            if integerPart.count > 1 && integerPart.hasPrefix("0") {
                throw error(.invalidNumber)
            }
            guard let d = Double(raw) else { throw error(.invalidNumber) }
            return .float(d)
        }
    }

    // MARK: - Arrays

    private mutating func parseArray() throws -> TOMLValue {
        _ = advance() // skip [
        var elements: [TOMLValue] = []
        while !isEOF {
            skipWhitespace(includeNewlines: true)
            guard let c = peek else { throw error(.unterminatedArray) }
            if c == "]" {
                _ = advance()
                return .array(elements)
            }
            let val = try parseValue()
            elements.append(val)
            skipWhitespace(includeNewlines: true)
            if peek == "," {
                _ = advance()
            } else if peek == "]" {
                _ = advance()
                return .array(elements)
            } else {
                throw error(.unterminatedArray)
            }
        }
        throw error(.unterminatedArray)
    }

    // MARK: - Inline Table

    private mutating func parseInlineTable() throws -> TOMLValue {
        _ = advance() // skip {
        var table: TOMLTable = [:]
        while !isEOF {
            skipWhitespace(includeNewlines: false)
            guard let c = peek else { throw error(.unterminatedInlineTable) }
            if c == "}" {
                _ = advance()
                return .table(table)
            }

            let keyPath = try parseKeyPath()
            skipWhitespace()
            guard peek == "=" else { throw error(.expectedEquals) }
            _ = advance()
            skipWhitespace()
            let val = try parseValue()
            try insert(value: val, at: keyPath, in: &table)

            skipWhitespace()
            if peek == "," {
                _ = advance()
            } else if peek == "}" {
                _ = advance()
                return .table(table)
            } else {
                throw error(.unterminatedInlineTable)
            }
        }
        throw error(.unterminatedInlineTable)
    }

    // MARK: - Table Hierarchy Helpers

    private mutating func ensureTable(in root: inout TOMLTable, path: [String]) throws {
        guard !path.isEmpty else { return }
        let first = path[0]
        let rest = Array(path.dropFirst())
        if rest.isEmpty {
            if let existing = root[first] {
                if case .table = existing { return }
                throw error(.conflictingTableDefinition(first))
            }
            root[first] = .table([:])
        } else {
            if let existing = root[first] {
                switch existing {
                case .table(var sub):
                    try ensureTable(in: &sub, path: rest)
                    root[first] = .table(sub)
                case .array(var arr):
                    guard !arr.isEmpty, case .table(var lastSub) = arr[arr.count - 1] else {
                        throw error(.conflictingTableDefinition(first))
                    }
                    try ensureTable(in: &lastSub, path: rest)
                    arr[arr.count - 1] = .table(lastSub)
                    root[first] = .array(arr)
                default:
                    throw error(.conflictingTableDefinition(first))
                }
            } else {
                var sub: TOMLTable = [:]
                try ensureTable(in: &sub, path: rest)
                root[first] = .table(sub)
            }
        }
    }

    private mutating func ensureArrayOfTables(in root: inout TOMLTable, path: [String]) throws {
        guard !path.isEmpty else { return }
        let first = path[0]
        let rest = Array(path.dropFirst())
        if rest.isEmpty {
            if let existing = root[first] {
                guard case .array(var arr) = existing else {
                    throw error(.conflictingTableDefinition(first))
                }
                arr.append(.table([:]))
                root[first] = .array(arr)
            } else {
                root[first] = .array([.table([:])])
            }
        } else {
            if let existing = root[first] {
                switch existing {
                case .table(var sub):
                    try ensureArrayOfTables(in: &sub, path: rest)
                    root[first] = .table(sub)
                case .array(var arr):
                    guard !arr.isEmpty, case .table(var lastSub) = arr[arr.count - 1] else {
                        throw error(.conflictingTableDefinition(first))
                    }
                    try ensureArrayOfTables(in: &lastSub, path: rest)
                    arr[arr.count - 1] = .table(lastSub)
                    root[first] = .array(arr)
                default:
                    throw error(.conflictingTableDefinition(first))
                }
            } else {
                var sub: TOMLTable = [:]
                try ensureArrayOfTables(in: &sub, path: rest)
                root[first] = .table(sub)
            }
        }
    }

    private mutating func insert(value: TOMLValue, at path: [String], in root: inout TOMLTable) throws {
        guard !path.isEmpty else { return }
        if path.count == 1 {
            let key = path[0]
            if root[key] != nil {
                throw error(.duplicateKey(key))
            }
            root[key] = value
            return
        }

        let first = path[0]
        let rest = Array(path.dropFirst())

        if let existing = root[first] {
            switch existing {
            case .table(var sub):
                try insert(value: value, at: rest, in: &sub)
                root[first] = .table(sub)
            case .array(var arr):
                guard !arr.isEmpty, case .table(var lastSub) = arr[arr.count - 1] else {
                    throw error(.conflictingTableDefinition(first))
                }
                try insert(value: value, at: rest, in: &lastSub)
                arr[arr.count - 1] = .table(lastSub)
                root[first] = .array(arr)
            default:
                throw error(.conflictingTableDefinition(first))
            }
        } else {
            var sub: TOMLTable = [:]
            try insert(value: value, at: rest, in: &sub)
            root[first] = .table(sub)
        }
    }
}
