import Foundation
import Synchronization

/// Runs a real process off the main actor. The child leads a process group of its own, so a cancel reaches what it
/// started too: a grandchild cannot keep the output pipes open and hang the run after the child itself is gone.
nonisolated struct SystemProcessRunner: ProcessRunning {
    /// How much of each output stream is kept; the rest is read and dropped so the process never blocks on a full pipe.
    static let maxOutputBytes = 64 * 1024

    /// How long a process gets to react to the termination request before it is killed.
    let killGrace: Duration

    init(killGrace: Duration = .seconds(2)) {
        self.killGrace = killGrace
    }

    func run(executable: String, arguments: [String]) async throws -> ProcessOutput {
        let child = ChildProcess()
        defer { child.finish() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let launched = try child.launch(executable: executable, arguments: arguments)
            async let standardOutput = Self.readAll(launched.output)
            async let standardError = Self.readAll(launched.errors)
            let (out, err) = await (standardOutput, standardError)
            let status = await Self.waitForExit(launched.pid)
            try Task.checkCancellation()
            return ProcessOutput(status: status, standardOutput: out, standardError: err)
        } onCancel: {
            child.cancel(killAfter: killGrace)
        }
    }

    /// Ends at the pipe's end of file, which the exit of the process (and its children) brings. Keeps the first
    /// `maxOutputBytes` and reads the rest only to drop it.
    private static func readAll(_ pipe: Pipe) async -> String {
        await blocking {
            let handle = pipe.fileHandleForReading
            var kept = Data()
            while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                kept.append(chunk.prefix(maxOutputBytes - kept.count))
            }
            return String(decoding: kept, as: UTF8.self)
        }
    }

    /// The exit code, or the number of the signal that ended the process (what `Process.terminationStatus` gives).
    private static func waitForExit(_ pid: pid_t) async -> Int32 {
        await blocking {
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1 {
                if errno != EINTR { return -1 }
            }
            // The low seven bits are zero after a normal exit and the signal number otherwise.
            let signal = status & 0x7f
            return signal == 0 ? (status >> 8) & 0xff : signal
        }
    }

    /// Reading a pipe or waiting for a child takes as long as the shortcut does, so it blocks a dispatch thread, not
    /// one of the few Swift concurrency threads that the rest of the app (and the kill timer) needs.
    private static func blocking<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: work()) }
        }
    }
}

/// One child process, shared by `run` and its cancellation handler. The state is behind a lock because the cancel
/// can arrive on any thread at any moment: before the launch, during it, or after the child has exited.
private nonisolated final class ChildProcess: Sendable {
    struct Launched {
        let pid: pid_t
        let output: Pipe
        let errors: Pipe
    }

    private enum State {
        case idle
        case running(pid_t)
        case cancelled
        case finished
    }

    private let state = Mutex(State.idle)

    /// Starts the program with no input, in a process group of its own. Throws `CancellationError` when the run was
    /// cancelled before this point.
    func launch(executable: String, arguments: [String]) throws -> Launched {
        let output = Pipe(), errors = Pipe()
        let pid = try state.withLock { state in
            guard case .idle = state else { throw CancellationError() }
            guard let pid = Self.spawn(
                executable, arguments,
                standardOutput: output.fileHandleForWriting.fileDescriptor,
                standardError: errors.fileHandleForWriting.fileDescriptor
            ) else { throw ShortcutsCLIError.launchFailed("Không mở được \(executable)") }
            state = .running(pid)
            return pid
        }
        // Only the child may keep the write ends, or the readers never see the end of file.
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()
        return Launched(pid: pid, output: output, errors: errors)
    }

    /// Asks the process group to end, and kills it when the run is still going after `grace`, so a child that ignores
    /// the request cannot hang the run. Uses a dispatch timer, which needs no free thread of the Swift pool.
    func cancel(killAfter grace: Duration) {
        let signalled = state.withLock { state in
            switch state {
            case .idle:
                state = .cancelled
                return false
            case .running(let pid):
                killpg(pid, SIGTERM)
                return true
            case .cancelled, .finished:
                return false
            }
        }
        guard signalled else { return }
        let nanoseconds = grace.components.seconds * 1_000_000_000 + grace.components.attoseconds / 1_000_000_000
        DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(nanoseconds))) { [self] in
            state.withLock { state in
                if case .running(let pid) = state { killpg(pid, SIGKILL) }
            }
        }
    }

    /// The run is over; nothing is signalled after this, so a process id that is free again is never hit.
    func finish() {
        state.withLock { $0 = .finished }
    }

    /// `posix_spawn` rather than `Process`, which cannot start a child in a new process group. The child gets the
    /// environment of the app, `/dev/null` for input, the pipes for output, and no other open file.
    private static func spawn(_ executable: String, _ arguments: [String], standardOutput: Int32, standardError: Int32) -> pid_t? {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, standardOutput, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, standardError, STDERR_FILENO)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        var allSignals = sigset_t(), noSignals = sigset_t()
        sigfillset(&allSignals)
        sigemptyset(&noSignals)
        posix_spawnattr_setsigdefault(&attributes, &allSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        posix_spawnattr_setpgroup(&attributes, 0)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT))

        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var pid: pid_t = 0
        return posix_spawn(&pid, executable, &actions, &attributes, argv, envp) == 0 ? pid : nil
    }
}
