/// Stable identifier of a feature module, e.g. "battery". Lowercase ASCII letters and digits only.
nonisolated public struct ModuleID: Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        precondition(
            !rawValue.isEmpty && rawValue.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) },
            "ModuleID must be non-empty lowercase ASCII letters or digits: \(rawValue)"
        )
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) { self.init(value) }

    public var description: String { rawValue }
}
