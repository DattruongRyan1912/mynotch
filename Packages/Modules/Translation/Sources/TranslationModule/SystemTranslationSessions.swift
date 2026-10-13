import Foundation
// `TranslationSession` isn't Sendable; it is created, cached and called from the main actor only.
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
