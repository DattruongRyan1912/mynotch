import Foundation
// `TranslationSession` and `LanguageAvailability` aren't Sendable. They are created and kept on the main actor, but
// their async methods run off it; `AppleTranslationEngine` runs one translation at a time, so a session never
// translates two texts at once.
@preconcurrency import Translation

/// The real Translation framework behind `AppleTranslationEngine`.
struct SystemTranslationSessions: TranslationSessionProviding {
    func status(from source: Locale.Language, to target: Locale.Language) async -> PairStatus {
        PairStatus(await LanguageAvailability().status(from: source, to: target))
    }

    func makeSession(from source: Locale.Language, to target: Locale.Language) -> any TranslatingSession {
        SystemTranslatingSession(TranslationSession(installedSource: source, target: target))
    }
}

/// A session that only uses installed language packs: it never shows the download sheet,
/// so it works without SwiftUI and throws `TranslationError.notInstalled` instead.
private final class SystemTranslatingSession: TranslatingSession {
    private let session: TranslationSession

    init(_ session: TranslationSession) { self.session = session }

    func translate(_ text: String) async throws -> String {
        try await session.translate(text).targetText
    }

    func cancel() { session.cancel() }
}

extension PairStatus {
    init(_ status: LanguageAvailability.Status) {
        switch status {
        case .installed: self = .installed
        case .supported: self = .supported
        case .unsupported: self = .unsupported
        @unknown default: self = .unsupported
        }
    }
}
