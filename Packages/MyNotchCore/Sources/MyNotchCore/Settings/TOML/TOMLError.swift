import Foundation

/// Syntax or parsing error encountered while decoding a TOML document.
nonisolated public struct TOMLError: Error, Equatable, Sendable, LocalizedError {
    public enum Kind: Equatable, Sendable {
        case unexpectedCharacter(Character)
        case unterminatedString
        case invalidEscape(String)
        case invalidNumber
        case invalidKey
        case expectedEquals
        case duplicateKey(String)
        case conflictingTableDefinition(String)
        case unterminatedArray
        case unterminatedInlineTable
        case trailingContent
        case nonFiniteFloatInJSON
    }

    public let line: Int
    public let column: Int
    public let kind: Kind

    public init(line: Int, column: Int, kind: Kind) {
        self.line = line
        self.column = column
        self.kind = kind
    }

    /// Privacy-safe summary suitable for logging (strictly static error kind, never contains user content).
    public var logSummary: String {
        "TOMLError at line \(line), column \(column): \(errorKindName)"
    }

    /// User-facing descriptive message for GUI error badges.
    public var errorDescription: String? {
        "TOMLError at line \(line), column \(column): \(kindDescription)"
    }

    private var errorKindName: String {
        switch kind {
        case .unexpectedCharacter: return "unexpected character"
        case .unterminatedString: return "unterminated string"
        case .invalidEscape: return "invalid escape sequence"
        case .invalidNumber: return "invalid number literal"
        case .invalidKey: return "invalid key syntax"
        case .expectedEquals: return "expected '=' after key"
        case .duplicateKey: return "duplicate key"
        case .conflictingTableDefinition: return "conflicting table definition"
        case .unterminatedArray: return "unterminated array"
        case .unterminatedInlineTable: return "unterminated inline table"
        case .trailingContent: return "unexpected trailing content"
        case .nonFiniteFloatInJSON: return "non-finite float in JSON"
        }
    }

    private var kindDescription: String {
        switch kind {
        case .unexpectedCharacter(let c):
            return "unexpected character '\(c)'"
        case .unterminatedString:
            return "unterminated string"
        case .invalidEscape(let esc):
            return "invalid escape sequence '\\\(esc)'"
        case .invalidNumber:
            return "invalid number literal"
        case .invalidKey:
            return "invalid key syntax"
        case .expectedEquals:
            return "expected '=' after key"
        case .duplicateKey(let key):
            return "duplicate key '\(key)'"
        case .conflictingTableDefinition(let path):
            return "conflicting table definition at '\(path)'"
        case .unterminatedArray:
            return "unterminated array"
        case .unterminatedInlineTable:
            return "unterminated inline table"
        case .trailingContent:
            return "unexpected trailing content"
        case .nonFiniteFloatInJSON:
            return "non-finite float (NaN/Inf) is not supported in JSON"
        }
    }
}
