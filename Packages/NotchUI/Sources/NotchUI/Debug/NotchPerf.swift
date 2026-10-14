import Foundation
import MyNotchCore

/// Debug-only counters of what keeps the notch busy: layout passes of its hosting view, evaluations of the root view's
/// body and redraws of the spectrum bars. Every 10 s a NOTICE line in category `perf` reports them per second
/// (`layouts/s=…, bodies/s=…, spectrumUpdates/s=…`), so a build on a real Mac says whether the notch lays out
/// continuously and what makes it. The line carries counts only, never content. Release builds compile it away.
public enum NotchPerf {
    nonisolated public enum Counter: String, CaseIterable, Sendable {
        /// `NSHostingView.layout()` of a notch panel. SwiftUI evaluates and lays out whatever changed inside it, so the
        /// rate is how often some view of the notch was invalidated or animated.
        case layouts
        /// `NotchRootView.body`: the whole notch re-evaluated. A state change does it; it never happens per frame.
        case bodies
        /// A redraw of the spectrum bars.
        case spectrumUpdates
    }

    /// Time between two report lines.
    public static let reportInterval: Duration = .seconds(10)

    #if DEBUG
    private static var counts: [Counter: Int] = [:]
    private static var reporter: Task<Void, Never>?
    private static let logger = Log.logger(category: "perf")
    /// Receives every report line as well; lets tests assert what was logged.
    static var sink: ((String) -> Void)?

    public static func count(_ counter: Counter) {
        counts[counter, default: 0] += 1
    }

    /// Starts the periodic report. Later calls do nothing.
    public static func start() {
        guard reporter == nil else { return }
        reporter = Task {
            let clock = ContinuousClock()
            var last = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: reportInterval)
                let now = clock.now
                report(over: last.duration(to: now))
                last = now
            }
        }
    }

    /// How often `counter` was counted since the last report.
    public static func counted(_ counter: Counter) -> Int { counts[counter, default: 0] }

    /// Logs the counts since the last report as rates over `elapsed`, then starts counting again.
    static func report(over elapsed: Duration) {
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let line = line(for: counts, over: seconds)
        counts = [:]
        logger.notice("\(line, privacy: .public)")
        sink?(line)
    }

    /// `layouts/s=12.3, bodies/s=0.0, spectrumUpdates/s=29.8`: every counter, one decimal.
    nonisolated static func line(for counts: [Counter: Int], over seconds: Double) -> String {
        Counter.allCases
            .map { "\($0.rawValue)/s=" + String(format: "%.1f", Double(counts[$0, default: 0]) / max(seconds, 0.001)) }
            .joined(separator: ", ")
    }
    #else
    @inlinable public static func count(_ counter: Counter) {}
    @inlinable public static func start() {}
    #endif
}
