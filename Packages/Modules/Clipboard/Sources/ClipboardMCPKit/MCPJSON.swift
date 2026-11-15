import Foundation

/// A JSON value, for what MCP leaves open: request parameters, tool arguments, schemas and results.
public enum JSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    /// Throws for text that is not one JSON value, and for values nested deeper than the decoder allows.
    public init(decoding data: Data) throws {
        self = try JSONDecoder().decode(JSON.self, from: data)
    }

    /// Compact text with sorted keys, so the same value is always the same bytes. U+2028 and U+2029 are written as escapes:
    /// JSON allows them raw, but some line readers split on them, and one message must stay on one line.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let text = String(decoding: try encoder.encode(self), as: UTF8.self)
        return Data(text.replacing("\u{2028}", with: "\\u2028").replacing("\u{2029}", with: "\\u2029").utf8)
    }

    public var string: String? {
        if case .string(let value) = self { value } else { nil }
    }

    /// A whole number, written as 4 or 4.0.
    public var int: Int? {
        switch self {
        case .int(let value): value
        case .double(let value): Int(exactly: value)
        default: nil
        }
    }

    public var object: [String: JSON]? {
        if case .object(let value) = self { value } else { nil }
    }

    public subscript(key: String) -> JSON? {
        object?[key]
    }
}

extension JSON: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSON].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
