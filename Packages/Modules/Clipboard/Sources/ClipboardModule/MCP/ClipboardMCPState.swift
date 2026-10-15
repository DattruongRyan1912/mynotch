import ClipboardMCPKit
import Foundation
import Observation

/// One call an agent made that reached the history. It holds the tool and how it went, never what was asked: the log is
/// there so the user can see that an agent looked, and a log of the questions would be one more place the clipboard leaks.
nonisolated struct ClipboardMCPAccess: Identifiable, Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        /// `hidden` is how many items matched the request and were held back for being secrets or looking like them.
        case answered(count: Int, hidden: Int = 0)
        /// A run of calls refused for coming too fast within one second, which is one row.
        case rateLimited(count: Int = 1)
    }

    let id: UUID
    let date: Date
    let tool: String
    let outcome: Outcome

    init(id: UUID = UUID(), date: Date, tool: String, outcome: Outcome) {
        self.id = id
        self.date = date
        self.tool = tool
        self.outcome = outcome
    }

    /// What the Settings row says besides the time and the tool.
    var summary: String {
        switch outcome {
        case .answered(let count, let hidden):
            let found = count == 0 ? "Không có kết quả" : "\(count) kết quả"
            return hidden == 0 ? found : "\(found) · \(hidden) mục bị ẩn vì có thể chứa bí mật"
        case .rateLimited(let count):
            let base = "Bị chặn: quá \(ClipboardMCPLimits.maxCallsPerSecond) lệnh gọi mỗi giây"
            return count > 1 ? "\(base) (× \(count))" : base
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

    /// Refusals of one second are one row with a count, and when the log is full an older refusal goes before a real call does, so
    /// a flood of refused calls cannot push out the ones that read the history.
    func record(tool: String, outcome: ClipboardMCPAccess.Outcome, at date: Date) {
        if case .rateLimited(let more) = outcome, let newest = entries.first, case .rateLimited(let count) = newest.outcome,
           Int(newest.date.timeIntervalSince1970) == Int(date.timeIntervalSince1970) {
            entries[0] = ClipboardMCPAccess(id: newest.id, date: newest.date, tool: newest.tool, outcome: .rateLimited(count: count + more))
            return
        }
        entries.insert(ClipboardMCPAccess(date: date, tool: tool, outcome: outcome), at: 0)
        guard entries.count > Self.maxEntries else { return }
        let olderRefusal = entries.indices.dropFirst().last { index in
            if case .rateLimited = entries[index].outcome { true } else { false }
        }
        entries.remove(at: olderRefusal ?? entries.count - 1)
    }

    func clearLog() {
        entries = []
    }
}
