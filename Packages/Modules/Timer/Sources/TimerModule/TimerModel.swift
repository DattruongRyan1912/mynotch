import Foundation

/// The timer's whole state as a value, so it can be saved and restored. Time is always passed in, never read.
/// Wall-clock dates are used on purpose: they stay correct across sleep and relaunch.
nonisolated enum TimerModel: Codable, Equatable {
    case idle
    case countdown(endDate: Date)
    case countdownPaused(remaining: TimeInterval)
    case finished
    case stopwatch(accumulated: TimeInterval, startedAt: Date)
    case stopwatchPaused(accumulated: TimeInterval)

    var isRunning: Bool {
        switch self {
        case .countdown, .stopwatch: true
        default: false
        }
    }

    var isCountdown: Bool {
        switch self {
        case .countdown, .countdownPaused, .finished: true
        default: false
        }
    }

    /// Starting while another timer exists replaces it.
    mutating func startCountdown(minutes: Int, now: Date) {
        self = .countdown(endDate: now.addingTimeInterval(TimeInterval(minutes) * 60))
    }

    mutating func startStopwatch(now: Date) {
        self = .stopwatch(accumulated: 0, startedAt: now)
    }

    mutating func pause(now: Date) {
        switch self {
        case .countdown(let endDate): self = .countdownPaused(remaining: max(0, endDate.timeIntervalSince(now)))
        case .stopwatch(let accumulated, let startedAt): self = .stopwatchPaused(accumulated: accumulated + now.timeIntervalSince(startedAt))
        default: break
        }
    }

    mutating func resume(now: Date) {
        switch self {
        case .countdownPaused(let remaining): self = .countdown(endDate: now.addingTimeInterval(remaining))
        case .stopwatchPaused(let accumulated): self = .stopwatch(accumulated: accumulated, startedAt: now)
        default: break
        }
    }

    mutating func cancel() { self = .idle }

    /// Adds a minute to a countdown; on a finished one it starts a new minute.
    mutating func addMinute(now: Date) {
        switch self {
        case .countdown(let endDate): self = .countdown(endDate: endDate.addingTimeInterval(60))
        case .countdownPaused(let remaining): self = .countdownPaused(remaining: remaining + 60)
        case .finished: startCountdown(minutes: 1, now: now)
        default: break
        }
    }

    /// Turns a countdown that is due into `.finished`; returns whether it did.
    mutating func refresh(now: Date) -> Bool {
        guard case .countdown(let endDate) = self, endDate <= now else { return false }
        self = .finished
        return true
    }

    func remaining(now: Date) -> TimeInterval {
        switch self {
        case .countdown(let endDate): max(0, endDate.timeIntervalSince(now))
        case .countdownPaused(let remaining): remaining
        default: 0
        }
    }

    func elapsed(now: Date) -> TimeInterval {
        switch self {
        case .stopwatch(let accumulated, let startedAt): accumulated + max(0, now.timeIntervalSince(startedAt))
        case .stopwatchPaused(let accumulated): accumulated
        default: 0
        }
    }
}

nonisolated enum TimerFormat {
    /// "m:ss", or "h:mm:ss" from one hour.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let (hours, minutes, secs) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
