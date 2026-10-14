import Foundation
import os
@testable import MediaModule

/// Collects what the Apple Music client logs, so tests can read it and prove it holds no secret.
final class FakeAppleMusicLog: AppleMusicLog {
    private(set) var entries: [(level: OSLogType, message: String)] = []

    var messages: [String] { entries.map(\.message) }

    func write(_ message: String, level: OSLogType) {
        entries.append((level, message))
    }

    func messages(at level: OSLogType) -> [String] {
        entries.filter { $0.level == level }.map(\.message)
    }
}
