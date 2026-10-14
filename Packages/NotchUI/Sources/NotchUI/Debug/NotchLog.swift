import Foundation
import MyNotchCore
import SwiftUI

/// Debug-only trace of what the notch does: state changes, window changes, window ordering. It exists to see what one
/// tab switch or resize really does on a machine, with a monotonic timestamp on every line. Release builds compile it
/// away. Lines carry states, module ids and geometry, never titles, clipboard text or any other content.
enum NotchLog {
    #if DEBUG
    private static let logger = Log.logger(category: "notch-ui")
    #endif

    /// Receives every line as well; lets tests assert what was logged.
    static var sink: ((String) -> Void)?

    /// Logs `message` at NOTICE level (kept by the unified log without extra flags) behind `t=<seconds since boot>`.
    static func record(_ message: @autoclosure () -> String) {
        #if DEBUG
        let line = "t=\(String(format: "%.3f", ProcessInfo.processInfo.systemUptime)) \(message())"
        logger.notice("\(line, privacy: .public)")
        sink?(line)
        #endif
    }
}

extension NotchState {
    /// `closed`, `compact`, `toast`, `open(<module id>)` or `open(-)`; module ids are the only variable part.
    var logDescription: String {
        switch self {
        case .closed: "closed"
        case .compact: "compact"
        case .toast: "toast"
        case .open(let id): "open(\(id?.rawValue ?? "-"))"
        }
    }
}

extension View {
    /// Logs when this view enters and leaves the hierarchy (debug builds only), which shows every identity change.
    func notchLogLifecycle(_ name: @autoclosure @escaping () -> String) -> some View {
        #if DEBUG
        onAppear { NotchLog.record("appear \(name())") }
            .onDisappear { NotchLog.record("disappear \(name())") }
        #else
        self
        #endif
    }
}

extension CGRect {
    /// `x,y WxH` with one decimal, compact enough for a log line.
    var logDescription: String {
        String(format: "%.1f,%.1f %.1fx%.1f", minX, minY, width, height)
    }
}
