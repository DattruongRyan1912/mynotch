import Foundation
import MyNotchCore

/// Debug-only trace of what the floating panel does around the keyboard: who has it, when a paste hands it back and what came of
/// it. It exists to see on a real machine why a paste did or did not go out, with a monotonic timestamp on every line, like the
/// notch's own trace (`keyboard hand-back` lines) it sits beside. Release builds compile it away. Lines carry states and window
/// geometry, never the clipboard's text, a title or a file name.
enum ClipboardPanelLog {
    #if DEBUG
    private static let logger = Log.logger(category: "clipboard-keyboard")
    #endif

    /// Receives every line as well; lets tests assert what was logged.
    static var sink: ((String) -> Void)?

    /// Logs `message` at NOTICE level (kept by the unified log without extra flags) behind `t=<seconds since boot>`, in the category `clipboard-keyboard`.
    static func record(_ message: @autoclosure () -> String) {
        #if DEBUG
        let line = "t=\(String(format: "%.3f", ProcessInfo.processInfo.systemUptime)) \(message())"
        logger.notice("\(line, privacy: .public)")
        sink?(line)
        #endif
    }
}
