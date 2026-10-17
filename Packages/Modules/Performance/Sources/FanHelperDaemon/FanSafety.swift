import Foundation

/// The rules the helper keeps whatever the app asks, as plain functions so they can be tried one by one.
public enum FanSafety {
    /// A speed held to a fan's own range.
    public static func clamp(_ rpm: Double, min low: Double, max high: Double) -> Double {
        Swift.min(Swift.max(rpm, low), high)
    }

    /// How far below Apple's speed a request may be before the fan is taken back to automatic. Apple's own speed moves by tens of rpm
    /// from one reading to the next; within this margin the fan is held at Apple's speed instead, so a request that hovers around it
    /// does not switch the fan between automatic and manual at every step.
    public static let takeBackMargin = 150.0

    public enum ForcedDecision: Equatable, Sendable {
        case force(Double)
        /// Do not force: the fan stays (or goes back to) automatic, for this reason.
        case automatic(String)
    }

    /// Never below Apple. A manual speed is only worth setting if it is not below what Apple's own control was doing when it was last
    /// seen (`baseline`, the fan's actual speed under automatic control). While the fan is held that speed cannot be seen, so it
    /// is only trusted while the die has not got `drift` degrees hotter than when it was read, which is when Apple would be spinning
    /// the fan faster: then the fan goes back to automatic for a moment to be looked at again.
    public static func forcedDecision(
        requested: Double, baseline: Double?, dieTemperature: Double?, baselineTemperature: Double?, drift: Double
    ) -> ForcedDecision {
        guard let baseline else { return .automatic("Apple's own speed cannot be read") }
        if let dieTemperature, let baselineTemperature, dieTemperature > baselineTemperature + drift {
            return .automatic("hotter than when Apple's speed was read")
        }
        if requested < baseline - takeBackMargin { return .automatic("Apple's own speed is higher") }
        return .force(max(requested, baseline))
    }

    /// The heat guard's state: on from `trip` degrees, off again below `release`, so it does not flicker around one value.
    public static func guardNext(active: Bool, temperature: Double, trip: Double, release: Double) -> Bool {
        if temperature >= trip { return true }
        if temperature < release { return false }
        return active
    }
}
