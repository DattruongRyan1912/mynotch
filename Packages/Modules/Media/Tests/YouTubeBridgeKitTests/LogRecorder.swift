import Foundation
import Synchronization
@testable import YouTubeBridgeKit

/// Collects what the bridge logs, so tests can read it and prove it holds nothing private.
final class LogRecorder: Sendable {
    private let storage = Mutex<[String]>([])

    var lines: [String] { storage.withLock { $0 } }

    var log: YouTubeBridgeLog {
        YouTubeBridgeLog { [self] line in storage.withLock { $0.append(line) } }
    }

    func lines(containing fragment: String) -> [String] { lines.filter { $0.contains(fragment) } }
}
