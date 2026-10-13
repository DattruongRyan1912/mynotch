/// Decides which battery live activities should be visible.
nonisolated struct BatteryActivityPolicy: Equatable, Sendable {
    /// Low-battery stays visible until the level rises this far above the threshold.
    static let hysteresis = 5

    var lowThreshold: Int
    var notifyOnCharge: Bool

    struct Decision: Equatable, Sendable {
        var showCharging: Bool
        var lowActive: Bool
    }

    func decide(previous: PowerSourceSnapshot?, current: PowerSourceSnapshot, lowActive: Bool) -> Decision {
        let pluggedIn = previous.map { !$0.isOnAC && current.isOnAC } ?? false
        let low: Bool
        if current.isOnAC {
            low = false
        } else if current.percent <= lowThreshold {
            low = true
        } else if lowActive, current.percent <= lowThreshold + Self.hysteresis {
            low = true
        } else {
            low = false
        }
        return Decision(showCharging: notifyOnCharge && pluggedIn, lowActive: low)
    }
}
