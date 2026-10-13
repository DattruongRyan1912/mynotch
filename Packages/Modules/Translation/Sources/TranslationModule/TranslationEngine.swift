import Foundation
// Translation predates Swift concurrency annotations; its types are only used on the main actor here.
@preconcurrency import Translation

/// Whether a language pair can be translated on this Mac.
nonisolated enum PairStatus: Equatable, Sendable {
    case installed
    /// Translation supports the pair but its language pack isn't downloaded yet.
    case supported
    case unsupported
}

/// Why a translation failed; the tab shows the first two as language-pack banners.
nonisolated enum TranslationFailure: Error, Equatable, Sendable {
    case notInstalled
    case unsupported
    case failed(String)
}

/// On-device translation; faked in module tests.
protocol TranslationEngine: AnyObject {
    func status(from source: Locale.Language, to target: Locale.Language) async -> PairStatus
    func translate(_ text: String, from source: Locale.Language, to target: Locale.Language) async throws(TranslationFailure) -> String
}

/// One translation session for a fixed pair.
protocol TranslatingSession: AnyObject {
    func translate(_ text: String) async throws -> String
}

/// The Translation framework calls `AppleTranslationEngine` makes, so its caching and error mapping are
/// testable without language packs.
protocol TranslationSessionProviding {
    func status(from source: Locale.Language, to target: Locale.Language) async -> PairStatus
    func makeSession(from source: Locale.Language, to target: Locale.Language) -> any TranslatingSession
}

/// Translates with Apple's on-device models. Keeps one session per pair, so a pair's model loads only once.
final class AppleTranslationEngine: TranslationEngine {
    private let sessions: any TranslationSessionProviding
    private var cache: [LanguagePair: any TranslatingSession] = [:]

    init(sessions: any TranslationSessionProviding = SystemTranslationSessions()) {
        self.sessions = sessions
    }

    func status(from source: Locale.Language, to target: Locale.Language) async -> PairStatus {
        await sessions.status(from: source, to: target)
    }

    func translate(_ text: String, from source: Locale.Language, to target: Locale.Language) async throws(TranslationFailure) -> String {
        let pair = LanguagePair(source: source, target: target)
        let session = cache[pair] ?? sessions.makeSession(from: source, to: target)
        cache[pair] = session
        do {
            return try await session.translate(text)
        } catch {
            let failure = TranslationFailure(error)
            switch failure {
            case .notInstalled, .unsupported:
                // This session can't work, and may not notice a pack installed later: start afresh next time.
                if cache[pair] === session { cache[pair] = nil }
            case .failed:
                break
            }
            throw failure
        }
    }
}

extension TranslationFailure {
    /// Maps Translation framework errors to the cases the tab distinguishes.
    init(_ error: any Error) {
        switch error {
        case TranslationError.notInstalled:
            self = .notInstalled
        case TranslationError.unsupportedSourceLanguage, TranslationError.unsupportedTargetLanguage,
             TranslationError.unsupportedLanguagePairing:
            self = .unsupported
        default:
            self = .failed(error.localizedDescription)
        }
    }
}
