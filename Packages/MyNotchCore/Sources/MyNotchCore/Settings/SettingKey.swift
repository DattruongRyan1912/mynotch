/// Typed settings key with a default value and an optional normalization (e.g. clamping).
nonisolated public struct SettingKey<Value: Codable & Sendable>: Sendable {
    public let name: String
    public let defaultValue: Value
    let normalize: @Sendable (Value) -> Value

    public init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
        self.normalize = { $0 }
    }
}

extension SettingKey where Value: Comparable {
    /// A key whose stored value is clamped into `range` when read.
    public init(_ name: String, default defaultValue: Value, clampedTo range: ClosedRange<Value>) {
        self.name = name
        self.defaultValue = defaultValue
        self.normalize = { min(max($0, range.lowerBound), range.upperBound) }
    }
}
