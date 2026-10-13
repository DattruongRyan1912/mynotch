import Foundation

nonisolated enum ShortcutsCLIError: Error, Equatable {
    /// The CLI exited with an error; the first line of what it said.
    case failed(String)
    case timedOut
    case launchFailed(String)

    /// Short text for the user.
    var message: String {
        switch self {
        case .failed(let message), .launchFailed(let message): message
        case .timedOut: "quá 60 giây"
        }
    }
}

/// The two things the module needs from `/usr/bin/shortcuts`. A protocol so tests never run it.
protocol ShortcutsCLI {
    func list() async throws -> [ShortcutInfo]
    /// Runs the shortcut and returns the text it produced, nil when there is none.
    func run(id: String) async throws -> String?
}

nonisolated struct ProcessOutput: Equatable, Sendable {
    let status: Int32
    let standardOutput: String
    let standardError: String
}

/// Starts a program and waits for it. Cancelling the task ends the program.
nonisolated protocol ProcessRunning: Sendable {
    func run(executable: String, arguments: [String]) async throws -> ProcessOutput
}

/// The real CLI: arguments go to `Process` as an array, never through a shell.
nonisolated struct SystemShortcutsCLI: ShortcutsCLI {
    static let executable = "/usr/bin/shortcuts"

    let runner: any ProcessRunning
    let timeout: Duration

    init(runner: any ProcessRunning = SystemProcessRunner(), timeout: Duration = .seconds(60)) {
        self.runner = runner
        self.timeout = timeout
    }

    func list() async throws -> [ShortcutInfo] {
        ShortcutListParser.parse(try await output(of: ["list", "--show-identifiers"]).standardOutput)
    }

    /// `id` comes from persisted settings, so it must be a list identifier (a UUID) before it can reach the command
    /// line, where a leading "-" would be read as an option.
    func run(id: String) async throws -> String? {
        guard UUID(uuidString: id) != nil else { throw ShortcutsCLIError.failed("Mã shortcut không hợp lệ") }
        let file = FileManager.default.temporaryDirectory.appending(path: "MyNotch-shortcut-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: file) }
        _ = try await output(of: ["run", id, "-o", file.path(percentEncoded: false), "--output-type", "public.plain-text"])
        // A shortcut can return any amount of text; only the first bytes are read. The cut may split a character,
        // so the decoding is lossy rather than failing.
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: SystemProcessRunner.maxOutputBytes) else { return nil }
        let trimmed = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Runs the CLI against the timeout; a non-zero exit becomes `failed` with the first line of its error output.
    private func output(of arguments: [String]) async throws -> ProcessOutput {
        let output = try await withThrowingTaskGroup(of: ProcessOutput?.self) { group in
            group.addTask { try await runner.run(executable: Self.executable, arguments: arguments) }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
        guard let output else { throw ShortcutsCLIError.timedOut }
        guard output.status == 0 else {
            let reason = output.standardError.split(whereSeparator: \.isNewline).first.map(String.init)?
                .trimmingCharacters(in: .whitespaces)
            throw ShortcutsCLIError.failed(reason.flatMap { $0.isEmpty ? nil : $0 } ?? "Mã thoát \(output.status)")
        }
        return output
    }
}
