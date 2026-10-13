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
            let lines = Self.lines(of: text).map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ") }
            return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        case .removeEmptyLines:
            return Self.lines(of: text).filter { !$0.allSatisfy(\.isWhitespace) }.joined(separator: "\n")
        case .sortLines:
            var lines = Self.lines(of: text)
            // A final line break is kept at the end rather than sorted to the top as an empty line.
            let endsWithLineBreak = lines.count > 1 && lines.last?.isEmpty == true
            if endsWithLineBreak { lines.removeLast() }
            lines.sort { $0.localizedStandardCompare($1) == .orderedAscending }
            return lines.joined(separator: "\n") + (endsWithLineBreak ? "\n" : "")
        case .jsonPretty:
            return Self.reserializeJSON(text, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        case .jsonMinify:
            // Sorted keys too: JSONSerialization does not keep the original key order, so this keeps output stable.
            return Self.reserializeJSON(text, options: [.sortedKeys, .withoutEscapingSlashes])
        case .base64Encode:
            return Data(text.utf8).base64EncodedString()
        case .base64Decode:
            // Copied Base64 is often wrapped over several lines.
            guard let data = Data(base64Encoded: String(text.filter { !$0.isWhitespace })) else { return nil }
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

    /// Only objects and arrays count as JSON, so plain words and numbers do not offer the JSON transforms.
    private static func reserializeJSON(_ text: String, options: JSONSerialization.WritingOptions) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
              let data = try? JSONSerialization.data(withJSONObject: object, options: options) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
