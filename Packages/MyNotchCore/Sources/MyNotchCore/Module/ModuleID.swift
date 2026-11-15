/// Stable identifier of a feature module, e.g. "battery". Lowercase ASCII letters and digits only.
/// "app" is reserved: app-level shortcuts use the "app_" name prefix.
nonisolated public struct ModuleID: Hashable, Sendable, Codable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    /// Returns nil for invalid ids; use for ids that come from runtime data.
    public init?(rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    /// For ids written in code; an invalid id is a programming error.
    public init(_ rawValue: String) {
        precondition(Self.isValid(rawValue), "ModuleID must be non-empty lowercase ASCII letters or digits, not \"app\": \(rawValue)")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) { self.init(value) }

    public var description: String { rawValue }

    static func isValid(_ rawValue: String) -> Bool {
        !rawValue.isEmpty
            && rawValue != "app"
            && rawValue.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }
    }
}
