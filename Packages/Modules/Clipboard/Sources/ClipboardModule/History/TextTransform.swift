import Foundation

/// Text conversions offered in a card's "Biến đổi" menu, in menu order.
nonisolated enum TextTransform: String, CaseIterable {
    case uppercase, lowercase, capitalizeWords, trimWhitespace, removeEmptyLines, sortLines
    case jsonPretty, jsonMinify, base64Encode, base64Decode, urlEncode, urlDecode

    var title: String {
        switch self {
        case .uppercase: "VIẾT HOA"
        case .lowercase: "viết thường"
        case .capitalizeWords: "Viết Hoa Chữ Đầu"
        case .trimWhitespace: "Bỏ khoảng trắng thừa"
        case .removeEmptyLines: "Bỏ dòng trống"
        case .sortLines: "Sắp xếp dòng"
        case .jsonPretty: "JSON: định dạng"
        case .jsonMinify: "JSON: thu gọn"
        case .base64Encode: "Base64: mã hoá"
        case .base64Decode: "Base64: giải mã"
        case .urlEncode: "URL: mã hoá"
        case .urlDecode: "URL: giải mã"
        }
    }

    /// nil when the transform does not apply, so the menu can disable it: text that is not a JSON object or array,
    /// invalid Base64 or percent-encoding, or decoded bytes that are not UTF-8. Line-based transforms join with "\n".
    func apply(_ text: String) -> String? {
        switch self {
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .capitalizeWords:
            return text.capitalized
        case .trimWhitespace:
            return Self.lines(of: text).map(Self.tidy).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        case .removeEmptyLines:
            return Self.lines(of: text).filter { !Self.isBlank($0) }.joined(separator: "\n")
        case .sortLines:
            // Trailing empty lines stay at the end rather than sorting to the top.
            let lines = Self.lines(of: text)
            let contentEnd = (lines.lastIndex { !Self.isBlank($0) } ?? -1) + 1
            let sorted = lines[..<contentEnd].sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            return (sorted + lines[contentEnd...]).joined(separator: "\n")
        case .jsonPretty:
            // JSONEncoder prints empty containers as "{\n\n}". Strings never hold a raw line break
            // (it is escaped), so joining these cannot change a value.
            return Self.reencodeJSON(text, formatting: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])?
                .replacing(/\{\n\n *\}/, with: "{}")
                .replacing(/\[\n\n *\]/, with: "[]")
        case .jsonMinify:
            // Sorted keys too: decoding does not keep the original key order, so this keeps output stable.
            return Self.reencodeJSON(text, formatting: [.sortedKeys, .withoutEscapingSlashes])
        case .base64Encode:
            return Data(text.utf8).base64EncodedString()
        case .base64Decode:
            // Copied Base64 is often wrapped over several lines; JWTs and URLs use base64url without padding.
            var base64 = String(text.compactMap { character -> Character? in
                switch character {
                case "-": "+"
                case "_": "/"
                case _ where character.isWhitespace: nil
                default: character
                }
            })
            base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
            guard let data = Data(base64Encoded: base64) else { return nil }
            return String(data: data, encoding: .utf8)
        case .urlEncode:
            return text.addingPercentEncoding(withAllowedCharacters: Self.urlUnreserved)
        case .urlDecode:
            return text.removingPercentEncoding
        }
    }

    /// RFC 3986 unreserved characters, so the result is safe as any URL component (spaces become "%20").
    private static let urlUnreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Splits on every line break, including "\r\n", keeping empty lines.
    private static func lines(of text: String) -> [Substring] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    }

    /// Lines hold no line breaks, so any whitespace left (spaces, tabs, no-break spaces) is horizontal.
    private static func isBlank(_ line: Substring) -> Bool {
        line.allSatisfy(\.isWhitespace)
    }

    /// Keeps the leading indentation (code stays readable), collapses later runs of whitespace to one space
    /// and drops trailing whitespace.
    private static func tidy(_ line: Substring) -> String {
        guard let contentStart = line.firstIndex(where: { !$0.isWhitespace }) else { return "" }
        return String(line[..<contentStart]) + line[contentStart...].split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Only objects and arrays count as JSON, so plain words and numbers do not offer the JSON transforms.
    private static func reencodeJSON(_ text: String, formatting: JSONEncoder.OutputFormatting) -> String? {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) else { return nil }
        switch value {
        case .object, .array:
            let encoder = JSONEncoder()
            encoder.outputFormatting = formatting
            return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) }
        case .string, .number, .bool, .null:
            return nil
        }
    }
}
