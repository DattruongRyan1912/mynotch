import MyNotchCore
import os

/// Why a selection shows nothing, as the short code the log carries. Every exit of a reading that is not a hint has one, so
/// that "selecting does nothing" can be explained from the unified log alone.
nonisolated enum SelectionSkip: String, Sendable, CaseIterable {
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
    /// A name or a heading: up to three capitalised words. Whether it needs no translation is only a guess.
    case shapeName = "shape-name"
    /// Not something written to be read: code, a log line, a path, a link, an identifier, or mostly numbers and marks.
    case shapeCode = "shape-code"
    /// One word that is not a name: too little for the recognizer to tell its language, so it gets the small button only.
    case shapeShort = "shape-short"
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

extension SelectionSkip {
    /// Whether a selection skipped for this reason gets the small translate button: when it is only a guess that nothing is
    /// worth translating (a name or heading, one word, a doubtful language, text in the user's own language, which they may
    /// want in another). Not for what is certainly nothing to translate (code, links, paths), nor for anything that
    /// was not read, was refused, or was already handled. Exhaustive on purpose: a new reason must be decided here.
    var offersButton: Bool {
        switch self {
        case .shapeName, .shapeShort, .lowConfidence, .sameLanguage, .noHint: true
        case .notTrusted, .noFrontApp, .ownApp, .denied, .cooldown, .secure, .unresponsive, .none, .tooLong, .blank, .unchanged,
             .shapeCode, .unsupportedLanguage, .noConversion, .cancelled: false
        }
    }
}

/// Why the on-device preview could not be made for text that is in another language.
nonisolated enum PreviewFailure: String, Sendable {
    case notInstalled = "not-installed"
    case unsupported
    case error
}

/// One line of the diagnostics log. It can only be made from a literal, which cannot hold anything chosen at run time, or by
/// one of the builders, which take codes and numbers: never a `String` that came from the user's text, an app's name, a
/// title or a path. An interpolated string does not compile as a line, so a later change cannot publish such a thing by
/// accident, which the `.public` of the log would otherwise do.
nonisolated struct SelectionLogLine: ExpressibleByStringLiteral, Sendable {
    let text: String

    init(stringLiteral value: StaticString) {
        text = "\(value)"
    }

    private init(text: String) {
        self.text = text
    }

    private static func flag(_ value: Bool) -> Int { value ? 1 : 0 }

    static func start(watcher: Bool, trusted: Bool, keys: Bool) -> Self {
        Self(text: "start watcher=\(flag(watcher)) trusted=\(flag(trusted)) keys=\(flag(keys))")
    }

    static func watcher(on: Bool, keys: Bool) -> Self {
        Self(text: on ? "watcher on keys=\(flag(keys))" : "watcher off")
    }

    static func gesture(pointer: Bool, keys: Bool) -> Self {
        Self(text: "gesture pointer=\(flag(pointer)) keys=\(flag(keys))")
    }

    static func skip(_ reason: SelectionSkip) -> Self {
        Self(text: "skip reason=\(reason.rawValue)")
    }

    static func hint(_ kind: SelectionHint.Kind) -> Self {
        Self(text: "hint kind=\(kind.logCode)")
    }

    static func previewFailed(_ reason: PreviewFailure) -> Self {
        Self(text: "preview failed reason=\(reason.rawValue)")
    }

    /// The small translate button came up, which is when it was seen, not when it was decided on.
    static func buttonShown(reason: SelectionSkip) -> Self {
        Self(text: "button shown reason=\(reason.rawValue)")
    }

    static func deny(added: Bool) -> Self {
        Self(text: "deny added=\(flag(added))")
    }

    /// Only the two attribute names that are ever set are logged; anything else is "other".
    static func accessibilityEnabled(_ attribute: String) -> Self {
        Self(text: "accessibility enabled attribute=\(known(attribute))")
    }

    static func accessibilityRefused(_ attribute: String) -> Self {
        Self(text: "accessibility refused attribute=\(known(attribute))")
    }

    private static func known(_ attribute: String) -> String {
        ["AXEnhancedUserInterface", "AXManualAccessibility"].contains(attribute) ? attribute : "other"
    }
}

/// Where "Bôi đen là hiểu" tells what it is doing. A protocol so tests read what is written; the real one is the unified log
/// (subsystem `io.lucasvu.mynotch`, category `smart-selection`, level notice, so it is kept and shows without a debug flag).
/// A line is made of fixed words and numbers (see `SelectionLogLine`), which is why the whole line is public.
protocol SelectionLog: AnyObject {
    func write(_ line: SelectionLogLine)
}

final class OSSelectionLog: SelectionLog {
    private let logger = Log.logger(category: "smart-selection")

    func write(_ line: SelectionLogLine) {
        logger.notice("\(line.text, privacy: .public)")
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
