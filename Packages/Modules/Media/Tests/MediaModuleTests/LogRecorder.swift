import Foundation
import Synchronization
import Testing
import YouTubeBridgeKit

/// Collects what the YouTube bridge logs, so tests can read it and prove it holds nothing private.
nonisolated final class LogRecorder: Sendable {
    private let storage = Mutex<[String]>([])

    var lines: [String] { storage.withLock { $0 } }

    var log: YouTubeBridgeLog {
        YouTubeBridgeLog { [self] line in storage.withLock { $0.append(line) } }
    }

    func lines(containing fragment: String) -> [String] { lines.filter { $0.contains(fragment) } }

    /// Fails for any line that holds one of `forbidden`, or a URL.
    func expectNothingPrivate(_ forbidden: [String], sourceLocation: SourceLocation = #_sourceLocation) {
        for line in lines {
            for text in forbidden + ["://", "http"] {
                #expect(!line.contains(text), "\(line.debugDescription) holds \(text)", sourceLocation: sourceLocation)
            }
        }
    }
}

/// A clock the test moves by hand, in seconds.
nonisolated final class TestClock: Sendable {
    private let seconds = Mutex(1_000.0)

    var now: TimeInterval { seconds.withLock { $0 } }

    func advance(by interval: TimeInterval) { seconds.withLock { $0 += interval } }
}
