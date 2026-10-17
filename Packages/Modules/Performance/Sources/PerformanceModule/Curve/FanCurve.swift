import Foundation

/// Who sets the fans.
nonisolated enum FanMode: String, Codable, CaseIterable, Equatable, Sendable {
    /// Apple's own control, which is what the Mac does with no help.
    case apple
    /// The user's curve, from the SoC temperature to a fan speed.
    case curve

    var title: String {
        switch self {
        case .apple: "Tự động của Apple"
        case .curve: "Đường cong của tôi"
        }
    }
}

/// From the SoC temperature to how fast the fans turn: nothing asked of them below `start`, rising evenly to their maximum at `full`.
nonisolated struct FanCurve: Equatable, Sendable {
    static let startRange = 30...90
    static let fullRange = 40...100
    /// The least between the two: a curve that jumps from nothing to the maximum in a degree is a switch, not a curve.
    static let minimumGap = 5

    var start: Int
    var full: Int

    /// Held to the ranges, with `full` at least `minimumGap` above `start`.
    var normalized: FanCurve {
        let start = min(max(start, Self.startRange.lowerBound), Self.startRange.upperBound)
        let full = min(max(max(full, start + Self.minimumGap), Self.fullRange.lowerBound), Self.fullRange.upperBound)
        return FanCurve(start: min(start, full - Self.minimumGap), full: full)
    }

    /// How much of the way from the fan's minimum to its maximum, 0 to 1.
    func fraction(at temperature: Double) -> Double {
        let curve = normalized
        return min(max((temperature - Double(curve.start)) / Double(curve.full - curve.start), 0), 1)
    }

    static let standard = FanCurve(start: 55, full: 85)
}

nonisolated enum FanCurvePreset: CaseIterable, Equatable, Sendable {
    case apple, cooler, veryCool, maximum

    var title: String {
        switch self {
        case .apple: "Mặc định Apple"
        case .cooler: "Mát hơn (50→80)"
        case .veryCool: "Rất mát (45→75)"
        case .maximum: "Tối đa"
        }
    }

    /// Nil for Apple's own: that is the mode, not a curve. "Tối đa" is a curve that reaches the maximum at 40 °C, which a Mac in use
    /// passes at once.
    var curve: FanCurve? {
        switch self {
        case .apple: nil
        case .cooler: FanCurve(start: 50, full: 80)
        case .veryCool: FanCurve(start: 45, full: 75)
        case .maximum: FanCurve(start: 30, full: 40)
        }
    }

    /// The preset that the mode and the two temperatures amount to, if any.
    static func matching(mode: FanMode, curve: FanCurve) -> FanCurvePreset? {
        guard mode == .curve else { return .apple }
        return allCases.first { $0.curve == curve.normalized }
    }
}

/// What the engine needs to know of a fan.
nonisolated struct FanLimits: Equatable, Sendable {
    let index: Int
    let minRPM: Double
    let maxRPM: Double
    /// The speed it has now: where a rise starts from.
    let currentRPM: Double
}

/// The curve in motion: smooths the temperature, decides when to take over and when to let go, and limits how fast the speed may
/// change. Pure: the time and the temperature come in, a directive for each fan goes out.
nonisolated struct FanCurveEngine: Equatable, Sendable {
    /// Time constant of the temperature's smoothing: a spike of a few seconds barely moves it.
    static let smoothingSeconds = 6.0
    /// The curve takes over at `start` and lets go below `start` minus this, so a temperature hovering at the line does not flap.
    static let hysteresis = 3.0
    static let maxRPMPerSecond = 400.0
    /// The longest time the speed may be allowed to change for in one step.
    static let longestStep = 3.0

    enum Directive: Equatable, Sendable {
        case automatic
        case rpm(Double)
    }

    private(set) var smoothed: Double?
    private(set) var isEngaged = false
    private var lastRPM: [Int: Double] = [:]
    private var lastTime: Date?

    mutating func reset() {
        self = FanCurveEngine()
    }

    mutating func step(temperature: Double, at now: Date, curve: FanCurve, fans: [FanLimits]) -> [Directive] {
        let seconds = lastTime.map { min(max(now.timeIntervalSince($0), 0.1), 10) } ?? 2
        lastTime = now
        if let previous = smoothed {
            let alpha = 1 - exp(-seconds / Self.smoothingSeconds)
            smoothed = previous + alpha * (temperature - previous)
        } else {
            smoothed = temperature
        }
        let value = smoothed ?? temperature
        let normalized = curve.normalized
        if value >= Double(normalized.start) { isEngaged = true } else if value < Double(normalized.start) - Self.hysteresis { isEngaged = false }
        guard isEngaged else {
            lastRPM = [:]
            return fans.map { _ in .automatic }
        }
        let fraction = normalized.fraction(at: value)
        // A long gap (the app was suspended) is not a licence for a long jump.
        let allowed = Self.maxRPMPerSecond * min(seconds, Self.longestStep)
        return fans.map { fan in
            let ideal = fan.minRPM + fraction * (fan.maxRPM - fan.minRPM)
            let previous = lastRPM[fan.index] ?? fan.currentRPM
            let next = min(max(ideal, previous - allowed), previous + allowed)
            let held = min(max(next, fan.minRPM), fan.maxRPM)
            lastRPM[fan.index] = held
            return .rpm(held)
        }
    }
}
