import Foundation
import Synchronization
@testable import ShortcutsModule

/// Stands in for the `shortcuts` binary: records every call and answers with `handler`, so no test starts a process.
nonisolated final class FakeProcessRunner: ProcessRunning {
    typealias Handler = @Sendable (_ executable: String, _ arguments: [String]) async throws -> ProcessOutput

    private let recorded = Mutex<[[String]]>([])
    private let handler: Handler

    init(_ handler: @escaping Handler) {
        self.handler = handler
    }

    /// Argument lists of every call so far, `executable` first.
    var calls: [[String]] { recorded.withLock { $0 } }

    func run(executable: String, arguments: [String]) async throws -> ProcessOutput {
        recorded.withLock { $0.append([executable] + arguments) }
        return try await handler(executable, arguments)
    }

    /// Never finishes by itself; ends only when the task is cancelled.
    static var hanging: FakeProcessRunner {
        FakeProcessRunner { _, _ in
            try await Task.sleep(for: .seconds(3600))
            return ProcessOutput(status: 0, standardOutput: "", standardError: "")
        }
    }

    /// Writes `text` where `-o` points, like `shortcuts run` does, then exits with `status`.
    static func writing(_ text: String?, status: Int32 = 0, standardError: String = "") -> FakeProcessRunner {
        FakeProcessRunner { _, arguments in
            if let text, let index = arguments.firstIndex(of: "-o") {
                try text.write(toFile: arguments[index + 1], atomically: true, encoding: .utf8)
            }
            return ProcessOutput(status: status, standardOutput: "", standardError: standardError)
        }
    }
}

/// The CLI as the module sees it. Runs wait for `release` when `gated`, so tests can look at the running state.
final class FakeShortcutsCLI: ShortcutsCLI {
    var listing: Result<[ShortcutInfo], any Error> = .success([])
    var listCount = 0
    private(set) var ran: [String] = []
    var outputs: [String: Result<String?, any Error>] = [:]
    var isGated = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func list() async throws -> [ShortcutInfo] {
        listCount += 1
        return try listing.get()
    }

    func run(id: String) async throws -> String? {
        ran.append(id)
        if isGated { await withCheckedContinuation { waiting.append($0) } }
        return try (outputs[id] ?? .success(nil)).get()
    }

    func release() {
        isGated = false
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

/// Lets tasks the module started finish. It polls, so it returns as soon as `condition` holds; the generous default only
/// matters on a machine so busy that a task takes seconds to get a turn, and a failing test pays it once.
func settle(timeout: Duration = .seconds(30), until condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(2))
    }
}
