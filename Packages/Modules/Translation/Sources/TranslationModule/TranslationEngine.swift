import Foundation
import Translation

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
    /// A newer request superseded this one, or its caller was cancelled: there is nothing to show.
    case cancelled
    case failed(String)
}

/// On-device translation; faked in module tests.
protocol TranslationEngine: AnyObject {
    func status(from source: Locale.Language, to target: Locale.Language) async -> PairStatus
    /// Blank text translates to "". A new request supersedes the one in flight, which fails with `.cancelled`.
    func translate(_ text: String, from source: Locale.Language, to target: Locale.Language) async throws(TranslationFailure) -> String
    /// Cancels the running translation and releases the sessions; call when the module stops.
    func invalidate()
}

/// An engine that translates on this Mac and sends the text nowhere. What a translation made without the user asking for it,
/// such as a preview beside a selection, must be made with: the engines that need the user's own key do not conform, so the
/// compiler keeps a selection's text from being sent anywhere by mistake.
protocol OnDeviceTranslationEngine: TranslationEngine {}

/// One translation session for a fixed pair.
protocol TranslatingSession: AnyObject {
    func translate(_ text: String) async throws -> String
    /// Ends the session for good: every later `translate` fails with `TranslationError.alreadyCancelled`.
    func cancel()
}

/// The Translation framework calls `AppleTranslationEngine` makes, so its caching and error mapping are
/// testable without language packs.
protocol TranslationSessionProviding {
    func status(from source: Locale.Language, to target: Locale.Language) async -> PairStatus
    func makeSession(from source: Locale.Language, to target: Locale.Language) -> any TranslatingSession
}

/// Translates with Apple's on-device models. Keeps one session per pair, so a pair's model loads only once,
/// and runs one translation at a time, so a session is never used concurrently.
final class AppleTranslationEngine: OnDeviceTranslationEngine {
    private let sessions: any TranslationSessionProviding
    private var cache: [LanguagePair: any TranslatingSession] = [:]
    /// The newest request; the next one waits for it to finish before touching a session.
    private var latest: Task<String, any Error>?

    init(sessions: any TranslationSessionProviding = SystemTranslationSessions()) {
        self.sessions = sessions
    }

    func status(from source: Locale.Language, to target: Locale.Language) async -> PairStatus {
        await sessions.status(from: source, to: target)
    }

    func translate(_ text: String, from source: Locale.Language, to target: Locale.Language) async throws(TranslationFailure) -> String {
        latest?.cancel()   // the latest request wins
        guard !text.allSatisfy(\.isWhitespace) else { return "" }
        let pair = LanguagePair(source: source, target: target)
        let previous = latest
        let request = Task {
            _ = await previous?.result
            try Task.checkCancellation()
            return try await self.run(text, pair)
        }
        latest = request
        do {
            // Cancelling the session would end it for every later request, so only this request is cancelled.
            return try await withTaskCancellationHandler { try await request.value } onCancel: { request.cancel() }
        } catch {
            throw TranslationFailure(error)
        }
    }

    func invalidate() {
        latest?.cancel()
        cache.values.forEach { $0.cancel() }
        cache.removeAll()
    }

    private func run(_ text: String, _ pair: LanguagePair) async throws(TranslationFailure) -> String {
        let session = cache[pair] ?? sessions.makeSession(from: pair.source, to: pair.target)
        cache[pair] = session
        do {
            let translation = try await session.translate(text)
            try Task.checkCancellation()   // superseded while the session worked: the result is stale
            return translation
        } catch {
            if Self.endsSession(error), cache[pair] === session { cache[pair] = nil }
            throw TranslationFailure(error)
        }
    }

    /// The session can't work any more, or (without a language pack) may not notice one installed later.
    private static func endsSession(_ error: any Error) -> Bool {
        switch error {
        case TranslationError.notInstalled, TranslationError.alreadyCancelled, TranslationError.unsupportedSourceLanguage,
             TranslationError.unsupportedTargetLanguage, TranslationError.unsupportedLanguagePairing:
            true
        default:
            false
        }
    }
}

extension TranslationFailure {
    /// Maps Translation framework and task errors to the cases the tab distinguishes.
    init(_ error: any Error) {
        switch error {
        case let failure as TranslationFailure:
            self = failure
        case is CancellationError, TranslationError.alreadyCancelled:
            self = .cancelled
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
