/// Decides which battery live activities should be visible.
nonisolated struct BatteryActivityPolicy: Equatable, Sendable {
    /// Low-battery stays visible until the level rises this far above the threshold.
    static let hysteresis = 5

    var lowThreshold: Int
    var notifyOnCharge: Bool
    var notifyAtEighty: Bool = false

    struct Decision: Equatable, Sendable {
        var showCharging: Bool
        var lowActive: Bool
        var showEightyAlert: Bool = false
    }

    /// "Plugged in" (isAttachedToAdapter) suppresses the low-battery activity even if the battery still drains under load.
    /// - Parameter previousThreshold: threshold used for the previous decision; when the user lowered it,
    ///   the hysteresis band no longer keeps an existing low activity alive.
    func decide(previous: PowerSourceSnapshot?, current: PowerSourceSnapshot, lowActive: Bool, previousThreshold: Int? = nil) -> Decision {
        let pluggedIn = previous.map { !$0.isAttachedToAdapter && current.isAttachedToAdapter } ?? false
        let thresholdLowered = previousThreshold.map { lowThreshold < $0 } ?? false
        let low: Bool
        if current.isAttachedToAdapter {
            low = false
        } else if current.percent <= lowThreshold {
            low = true
        } else if lowActive, !thresholdLowered, current.percent <= lowThreshold + Self.hysteresis {
            low = true
        } else {
            low = false
        }

        let reachedEighty = current.isAttachedToAdapter && current.percent >= 80 && (previous.map { $0.percent < 80 } ?? false)
        let eightyAlert = notifyAtEighty && reachedEighty

        return Decision(showCharging: notifyOnCharge && pluggedIn, lowActive: low, showEightyAlert: eightyAlert)
    }
}
