import MyNotchCore
import os

/// Where the engines' diagnostics go. A protocol so tests can read what is written; the real one is the unified log
/// (subsystem `io.lucasvu.mynotch`, category `translation`).
///
/// A message holds the engine's name and a status or a kind of failure, nothing else: never a key, a header, the text
/// being translated or the words of a service's answer. That is why the whole message is public.
nonisolated protocol TranslationLog: Sendable {
    func write(_ message: String, level: OSLogType)
}

nonisolated struct OSTranslationLog: TranslationLog {
    func write(_ message: String, level: OSLogType) {
        Log.logger(category: "translation").log(level: level, "\(message, privacy: .public)")
    }
}
