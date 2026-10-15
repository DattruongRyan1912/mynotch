import Foundation
@testable import TranslationModule

/// Stands in for Dictionary Services: tests set what each term is defined as and read what was asked. The first
/// lookups can be held until `release()`, like a slow dictionary.
nonisolated final class FakeDictionary: DictionaryLooking, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String: String] = [:]
    private var asked: [String] = []
    private var isHolding = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var definitions: [String: String] {
        get { lock.withLock { answers } }
        set { lock.withLock { answers = newValue } }
    }

    var requests: [String] { lock.withLock { asked } }
    var holds: Bool {
        get { lock.withLock { isHolding } }
        set { lock.withLock { isHolding = newValue } }
    }

    var waiting: Int { lock.withLock { waiters.count } }

    func definition(of term: String) async -> String? {
        lock.withLock { asked.append(term) }
        await withCheckedContinuation { continuation in
            let resumesAtOnce = lock.withLock {
                guard isHolding else { return true }
                waiters.append(continuation)
                return false
            }
            if resumesAtOnce { continuation.resume() }
        }
        return lock.withLock { answers[term] }
    }

    /// Lets every held lookup answer, and stops holding.
    func release() {
        let released = lock.withLock {
            isHolding = false
            defer { waiters = [] }
            return waiters
        }
        released.forEach { $0.resume() }
    }
}

/// Records the URLs the module asks the system to open instead of launching an app.
final class FakeURLOpener: URLOpening {
    private(set) var opened: [URL] = []

    func open(_ url: URL) {
        opened.append(url)
    }
}
