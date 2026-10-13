import Foundation
@testable import TranslationModule

/// Echoes the text with its direction, or throws the failure set for its text. Like the real engine, a new request
/// wins over the one in flight, which then fails with `.cancelled`.
final class FakeEngine: TranslationEngine {
    struct Request: Equatable {
        var text: String
        var pair: LanguagePair
    }

    var statuses: [LanguagePair: PairStatus] = [:]
    /// Thrown for requests whose text matches, before any `failure`.
    var failures: [String: TranslationFailure] = [:]
    /// Thrown for every request when set.
    var failure: TranslationFailure?
    /// When true, requests wait for `release()`.
    var holds = false
    private(set) var requests: [Request] = []
    private(set) var invalidations = 0
    private var held: CheckedContinuation<Bool, Never>?

    var waiting: Bool { held != nil }

    func status(from source: Locale.Language, to target: Locale.Language) async -> PairStatus {
        statuses[LanguagePair(source: source, target: target)] ?? .installed
    }

    func translate(_ text: String, from source: Locale.Language, to target: Locale.Language) async throws(TranslationFailure) -> String {
        let pair = LanguagePair(source: source, target: target)
        requests.append(Request(text: text, pair: pair))
        held?.resume(returning: false)
        held = nil
        if holds {
            let released = await withCheckedContinuation { held = $0 }
            guard released else { throw .cancelled }
        }
        if let failure = failures[text] ?? failure { throw failure }
        return "\(text) [\(source.minimalIdentifier)→\(target.minimalIdentifier)]"
    }

    func invalidate() {
        invalidations += 1
        held?.resume(returning: false)
        held = nil
    }

    /// Lets the waiting request finish.
    func release() {
        held?.resume(returning: true)
        held = nil
    }
}

/// Records what the module asks to install instead of showing a window.
final class FakeInstaller: LanguageInstalling {
    private(set) var pairs: [LanguagePair] = []
    private(set) var onStatusChange: (@MainActor () -> Void)?

    func install(_ pair: LanguagePair, onStatusChange: @escaping @MainActor () -> Void) {
        pairs.append(pair)
        self.onStatusChange = onStatusChange
    }
}

extension Locale.Language {
    static let vi = Locale.Language(identifier: "vi")
    static let en = Locale.Language(identifier: "en")
    static let ja = Locale.Language(identifier: "ja")
}

/// Waits for main-actor work started by the code under test (tasks, observations) to make `condition` true.
func eventually(_ condition: () -> Bool) async {
    for _ in 0..<200 where !condition() { await Task.yield() }
}
