import MyNotchCore
import os

/// Where the Apple Music diagnostics go. A protocol so tests can read what is written; the real one is the unified log
/// (subsystem `io.lucasvu.mynotch`, category `media`).
///
/// A message holds no token, cookie, header value, TTML or lyrics: only statuses, Apple's error title and code, the
/// storefront, whether a user token was attached and how long it is, the user agent and variant names. That is why
/// the whole message is public.
protocol AppleMusicLog {
    func write(_ message: String, level: OSLogType)
}

struct OSAppleMusicLog: AppleMusicLog {
    private let logger = Log.logger(category: "media")

    func write(_ message: String, level: OSLogType) {
        logger.log(level: level, "\(message, privacy: .public)")
    }
}
