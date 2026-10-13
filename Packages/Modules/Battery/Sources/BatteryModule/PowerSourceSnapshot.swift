/// One reading of the internal battery.
nonisolated public struct PowerSourceSnapshot: Equatable, Sendable {
    public var percent: Int
    public var isCharging: Bool
    /// Plugged into a power adapter (may be "not charging" when held at a limit).
    public var isOnAC: Bool
    /// Minutes; nil while macOS is still estimating or when the value does not apply (e.g. on AC).
    public var minutesToEmpty: Int?
    public var minutesToFull: Int?

    public init(percent: Int, isCharging: Bool, isOnAC: Bool, minutesToEmpty: Int? = nil, minutesToFull: Int? = nil) {
        self.percent = percent
        self.isCharging = isCharging
        self.isOnAC = isOnAC
        self.minutesToEmpty = minutesToEmpty
        self.minutesToFull = minutesToFull
    }
}
