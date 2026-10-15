import ClipboardMCPKit
import Foundation
import Observation

/// One call an agent made that reached the history. It holds the tool and how it went, never what was asked: the log is
/// there so the user can see that an agent looked, and a log of the questions would be one more place the clipboard leaks.
nonisolated struct ClipboardMCPAccess: Identifiable, Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        case answered(count: Int)
        case rateLimited
    }

    let id = UUID()
    let date: Date
    let tool: String
    let outcome: Outcome

    /// What the Settings row says besides the time and the tool.
    var summary: String {
        switch outcome {
        case .answered(let count): count == 0 ? "Không có kết quả" : "\(count) kết quả"
        case .rateLimited: "Bị chặn: quá \(ClipboardMCPLimits.maxCallsPerSecond) lệnh gọi mỗi giây"
        }
    }
}

/// What Settings shows about the agents' access: the log, and why it does not work when it does not. The module owns it and
/// it outlives the module's running, so Settings can show the last calls of a module that has stopped.
@Observable
final class ClipboardMCPState {
    static let maxEntries = 50

    /// Newest first, at most `maxEntries`.
    private(set) var entries: [ClipboardMCPAccess] = []
    /// Whether the socket is open: the feature is on and the module runs.
    var isListening = false
    /// Why the socket could not be opened.
    var listenFailure: String?
    /// Why the helper could not be put where the agents' configuration points to.
    var helperFailure: String?

    func record(tool: String, outcome: ClipboardMCPAccess.Outcome, at date: Date) {
        entries.insert(ClipboardMCPAccess(date: date, tool: tool, outcome: outcome), at: 0)
        if entries.count > Self.maxEntries { entries.removeLast(entries.count - Self.maxEntries) }
    }

    func clearLog() {
        entries = []
    }
}
