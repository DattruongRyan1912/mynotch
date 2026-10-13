import Foundation

/// Lenient readers for the agents' undocumented JSON: a field that is missing or of an unexpected type reads as
/// absent instead of failing the whole record, which a strict `Decodable` model would do.
nonisolated enum JSONFields {
    private static let fractionalISO8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func object(from line: String) -> [String: Any]? {
        object(from: Data(line.utf8))
    }

    static func object(from data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// The elements that are objects; anything else in the array is skipped.
    static func objects(_ value: Any?) -> [[String: Any]] {
        (value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    /// A non-empty string, or nil.
    static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    /// A token count; missing or non-numeric counts read as zero.
    static func count(_ value: Any?) -> Int {
        value as? Int ?? 0
    }

    /// An ISO 8601 string with or without fractional seconds, or a Unix time in seconds or milliseconds.
    static func date(_ value: Any?) -> Date? {
        if let text = value as? String {
            return (try? Date(text, strategy: fractionalISO8601)) ?? (try? Date(text, strategy: .iso8601))
        }
        guard let number = value as? Double, number > 0 else { return nil }
        // 1e11 seconds is past the year 5000, so larger numbers are milliseconds.
        return Date(timeIntervalSince1970: number > 1e11 ? number / 1000 : number)
    }
}
