import MyNotchCore
import os

/// Why a selection shows nothing, as the short code the log carries. Every exit of a reading that is not a hint has one, so
/// that "selecting does nothing" can be explained from the unified log alone.
nonisolated enum SelectionSkip: String, Sendable {
    case notTrusted = "not-trusted"
    case noFrontApp = "no-front-app"
    case ownApp = "own-app"
    case denied
    case cooldown
    case secure
    case unresponsive
    /// Nothing selected, a password field, or an app that does not say.
    case none
    case tooLong = "too-long"
    case blank
    case unchanged
    /// Not something written to be read: a link, a path, code, a log line, a name, one word.
    case shape
    case sameLanguage = "same-language"
    /// The recognizer is not sure enough, or the text has no accents and is held to more.
    case lowConfidence = "low-confidence"
    /// In a language Translation cannot translate.
    case unsupportedLanguage = "unsupported-language"
    /// A quantity that could not be converted, such as a price with no rates.
    case noConversion = "no-conversion"
    case cancelled
    case noHint = "no-hint"
}

/// Why the on-device preview could not be made for text that is in another language.
nonisolated enum PreviewFailure: String, Sendable {
    case notInstalled = "not-installed"
    case unsupported
    case error
}

/// Where "Bôi đen là hiểu" tells what it is doing. A protocol so tests read what is written; the real one is the unified log
/// (subsystem `io.lucasvu.mynotch`, category `smart-selection`, level notice, so it is kept and shows without a debug flag).
///
/// A line is made of fixed words and numbers: a code for why or what, never the text selected, a name, a title or a path. That
/// is why the whole line is public.
protocol SelectionLog: AnyObject {
    func write(_ line: String)
}

final class OSSelectionLog: SelectionLog {
    private let logger = Log.logger(category: "smart-selection")

    func write(_ line: String) {
        logger.notice("\(line, privacy: .public)")
    }
}

/// Notices that are shown once for the whole run of the app, however often the module that shows them starts again.
final class SelectionNotices {
    private var claimed = false

    /// True the first time, false ever after.
    func claim() -> Bool {
        defer { claimed = true }
        return !claimed
    }
}
