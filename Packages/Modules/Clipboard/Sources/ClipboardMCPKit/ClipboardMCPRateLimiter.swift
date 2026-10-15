/// At most `maxCalls` in any `window` seconds. The helper keeps one, and so does the app, which does not trust that the
/// helper did.
public struct ClipboardMCPRateLimiter: Sendable {
    private let maxCalls: Int
    private let window: Double
    /// When the calls that count were made, oldest first.
    private var calls: [Double] = []

    public init(maxCalls: Int = ClipboardMCPLimits.maxCallsPerSecond, window: Double = 1) {
        self.maxCalls = maxCalls
        self.window = window
    }

    /// Whether a call at `time` (monotonic seconds) may go on. A refused call is not counted, so a flood does not keep the
    /// gate shut after it stops. A time before the latest call is taken as that call's time, so a clock that steps back does
    /// not let more through.
    public mutating func allow(at time: Double) -> Bool {
        let now = max(time, calls.last ?? time)
        calls.removeAll { now - $0 >= window }
        guard calls.count < maxCalls else { return false }
        calls.append(now)
        return true
    }
}
