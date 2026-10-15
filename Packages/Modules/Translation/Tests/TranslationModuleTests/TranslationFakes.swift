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

/// Stands in for the selection reader's retry pauses: returns at once unless `holds`, then waits for `release()`
/// or for the read to be cancelled.
final class PauseGate {
    var holds = false
    private var waiting: CheckedContinuation<Void, any Error>?

    var isWaiting: Bool { waiting != nil }

    func pause() async throws {
        guard holds else { return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiting = $0 }
        } onCancel: {
            Task { @MainActor in self.finish(throwing: CancellationError()) }
        }
    }

    func release() {
        finish(throwing: nil)
    }

    private func finish(throwing error: (any Error)?) {
        guard let waiting else { return }
        self.waiting = nil
        if let error { waiting.resume(throwing: error) } else { waiting.resume() }
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

/// Lets every task the code under test started run, so a check that nothing happened isn't vacuous: the engine
/// records a request only once the translation task runs.
func settle() async {
    for _ in 0..<50 { await Task.yield() }
}

/// Waits for work that runs on another thread (reading a text for quantities) to make `condition` true, which yielding
/// to the main actor cannot wait for. Bounded at two seconds.
func eventuallyOnAnotherThread(_ condition: () -> Bool) async {
    for _ in 0..<400 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
}

/// Reads quantities like the real recognizer and records every call, on which thread, so tests can see when a text is
/// read and that it is not on the main thread. The first call can be held until `release()`, like a slow reading.
nonisolated final class SpyRecognizer: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String] = []
    private var threads: [Bool] = []
    private var held: DispatchSemaphore?
    private var hasHeld = false

    var calls: [String] { lock.withLock { texts } }
    var ranOnTheMainThread: Bool { lock.withLock { threads.contains(true) } }

    func holdFirstCall() {
        lock.withLock { held = DispatchSemaphore(value: 0) }
    }

    func release() {
        lock.withLock { held }?.signal()
    }

    func recognize(_ text: String, _ currency: Bool) -> Recognition {
        let semaphore: DispatchSemaphore? = lock.withLock {
            texts.append(text)
            threads.append(Thread.isMainThread)
            guard let held, !hasHeld else { return nil }
            hasHeld = true
            return held
        }
        // Bounded, so a reading that wrongly runs on the thread that has to release it fails the test instead of hanging it.
        _ = semaphore?.wait(timeout: .now() + 3)
        return QuantityRecognizer.recognize(text, currency: currency)
    }
}
