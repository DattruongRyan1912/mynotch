import Darwin
import Foundation
import MyNotchCore

/// Runs mediaremote-adapter through Apple-signed `/usr/bin/perl`, the only way left for an app to read
/// MediaRemote on macOS 15.4+. Keeps `stream` running, restarting it with backoff, and runs `send`/`seek`
/// as short separate processes.
final class AdapterProcess: NowPlayingSource {
    /// An exit this soon after a launch means the adapter could not start (e.g. Apple blocked it).
    static let startupWindow: Duration = .seconds(2)
    /// Failed starts in a row before giving up.
    static let startupFailureLimit = 3
    /// Staying up this long proves the adapter works, so the next restart is quick again.
    static let stableUptime: Duration = .seconds(60)

    /// 1, 2, 4, 8, 16, then 30 seconds for every later restart.
    static func restartDelay(attempt: Int) -> Duration {
        .seconds(min(1 << min(attempt, 5), 30))
    }

    let executable: URL
    /// Arguments before the adapter command: the script and framework paths.
    let baseArguments: [String]
    private let scheduler: any Scheduler
    /// How long `stop()` lets the stream handle SIGTERM before killing it.
    private let killDelay: Duration
    private let log: @MainActor (String) -> Void
    private let environment: [String: String]

    private var onLine: (@MainActor (String) -> Void)?
    private var onFailure: (@MainActor (String) -> Void)?
    private var stream: Process?
    /// Stream launches so far; also identifies the current launch so an older process's late output is dropped.
    private(set) var launchCount = 0
    private var restartAttempt = 0
    private var startupFailures = 0
    private var isStarting = false
    /// Startup window, uptime and restart timers; all cancelled on exit and stop.
    private var timers: [ScheduledAction] = []
    /// Commands waiting for the running one, oldest first; at most one of them is a seek.
    private var queuedCommands: [(arguments: [String], isSeek: Bool)] = []
    private var isRunningCommand = false

    convenience init(
        perl: URL = URL(filePath: "/usr/bin/perl"),
        script: URL,
        framework: URL,
        scheduler: any Scheduler,
        log: @escaping @MainActor (String) -> Void = AdapterProcess.defaultLog
    ) {
        self.init(executable: perl, baseArguments: [script.path, framework.path], scheduler: scheduler, log: log)
    }

    /// Runs `executable baseArguments… <command>`; tests pass `/bin/sh` and a fake adapter script.
    init(
        executable: URL,
        baseArguments: [String],
        scheduler: any Scheduler,
        killDelay: Duration = .seconds(1),
        log: @escaping @MainActor (String) -> Void = AdapterProcess.defaultLog
    ) {
        self.executable = executable
        self.baseArguments = baseArguments
        self.scheduler = scheduler
        self.killDelay = killDelay
        self.log = log
        self.environment = Self.adapterEnvironment(from: ProcessInfo.processInfo.environment)
    }

    /// A dropped source must not leave perl running.
    isolated deinit { stop() }

    private static let logger = Log.logger(category: "media")

    static func defaultLog(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    /// Variables that load code into perl, or that the adapter reads as its own options and test hooks.
    private nonisolated static let blockedVariables: Set<String> = ["PERL5OPT", "PERL5LIB", "PERLLIB", "PERL5DB", "ADAPTER_TEST_MODE"]

    /// The app's environment minus anything that could change what perl or the adapter runs.
    nonisolated static func adapterEnvironment(from environment: [String: String]) -> [String: String] {
        environment.filter { key, _ in !blockedVariables.contains(key) && !key.hasPrefix("MEDIAREMOTEADAPTER_") }
    }

    var streamArguments: [String] { baseArguments + ["stream", "--micros", "--debounce=100"] }

    func arguments(for command: MediaCommand) -> [String] { baseArguments + ["send", String(command.rawValue)] }

    /// The adapter takes a non-negative whole number of microseconds; nil when the position has none
    /// (not finite, or too far for `Int64`, where converting would trap).
    func seekArguments(toSeconds seconds: Double) -> [String]? {
        guard seconds.isFinite, let micros = Int64(exactly: (max(seconds, 0) * 1_000_000).rounded()) else { return nil }
        return baseArguments + ["seek", String(micros)]
    }

    /// Whether a stream process is running (for tests).
    var isStreamRunning: Bool { stream != nil }

    func start(onLine: @escaping @MainActor (String) -> Void, onFailure: @escaping @MainActor (String) -> Void) {
        stop()
        self.onLine = onLine
        self.onFailure = onFailure
        restartAttempt = 0
        startupFailures = 0
        launch()
    }

    func stop() {
        onLine = nil
        onFailure = nil
        // A command still running finishes; ones waiting behind it are for a session that is over.
        queuedCommands = []
        cancelTimers()
        guard let stream else { return }
        self.stream = nil
        stream.terminate()
        // `stream` exits on SIGTERM (README); kill it if it hangs, without blocking the main actor.
        Task.detached { [killDelay] in
            try? await Task.sleep(for: killDelay)
            if stream.isRunning { kill(stream.processIdentifier, SIGKILL) }
        }
    }

    func send(_ command: MediaCommand) {
        enqueue(arguments(for: command), isSeek: false)
    }

    func seek(toSeconds seconds: Double) {
        guard let arguments = seekArguments(toSeconds: seconds) else {
            log("Ignored seek to \(seconds) seconds")
            return
        }
        enqueue(arguments, isSeek: true)
    }

    private func launch() {
        guard onLine != nil else { return }
        launchCount += 1
        let id = launchCount
        let process = Process()
        process.executableURL = executable
        process.arguments = streamArguments
        process.environment = environment
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let exited: @MainActor (Bool, String) -> Void = { [weak self] succeeded, reason in
            self?.streamExited(id, succeeded: succeeded, reason: reason)
        }
        process.terminationHandler = { process in
            let (succeeded, reason) = Self.outcome(of: process)
            DispatchQueue.main.async { exited(succeeded, reason) }
        }
        isStarting = true
        timers.append(scheduler.schedule(after: Self.startupWindow) { [weak self] in self?.isStarting = false })
        timers.append(scheduler.schedule(after: Self.stableUptime) { [weak self] in self?.restartAttempt = 0 })
        do {
            try process.run()
        } catch {
            log("Could not launch the media adapter: \(error.localizedDescription)")
            streamExited(id, succeeded: false, reason: "launch failed")
            return
        }
        stream = process
        Self.readLines(from: output.fileHandleForReading) { [weak self] lines in self?.deliver(lines, from: id) }
        Self.readLines(from: errors.fileHandleForReading) { [log] lines in lines.forEach(log) }
    }

    private func deliver(_ lines: [String], from id: Int) {
        for line in lines {
            // Re-checked per line: a callback may stop the source.
            guard id == launchCount, let onLine else { return }
            onLine(line)
        }
    }

    private func streamExited(_ id: Int, succeeded: Bool, reason: String) {
        guard id == launchCount, onLine != nil else { return }
        stream = nil
        cancelTimers()
        startupFailures = !succeeded && isStarting ? startupFailures + 1 : 0
        if startupFailures >= Self.startupFailureLimit {
            let onFailure = onFailure
            stop()
            onFailure?("The media adapter failed to start \(Self.startupFailureLimit) times in a row (\(reason)).")
            return
        }
        let delay = Self.restartDelay(attempt: restartAttempt)
        restartAttempt += 1
        log("The media adapter exited (\(reason)); restarting in \(delay)")
        timers.append(scheduler.schedule(after: delay) { [weak self] in self?.launch() })
    }

    private func cancelTimers() {
        timers.forEach { $0.cancel() }
        timers = []
    }

    /// Commands run one at a time so the player gets them in order. A new seek replaces a seek still waiting,
    /// so dragging the progress bar keeps at most one seek waiting behind the running command.
    private func enqueue(_ arguments: [String], isSeek: Bool) {
        if isSeek { queuedCommands.removeAll { $0.isSeek } }
        queuedCommands.append((arguments, isSeek))
        runNextCommand()
    }

    private func runNextCommand() {
        guard !isRunningCommand, !queuedCommands.isEmpty else { return }
        isRunningCommand = true
        runOnce(queuedCommands.removeFirst().arguments) { [weak self] in
            self?.isRunningCommand = false
            self?.runNextCommand()
        }
    }

    /// Runs one command and calls `finished` when it is over; the result only matters when it failed.
    private func runOnce(_ arguments: [String], finished: @escaping @MainActor () -> Void) {
        let command = arguments.dropFirst(baseArguments.count).joined(separator: " ")
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        let log = log
        process.terminationHandler = { process in
            let (succeeded, reason) = Self.outcome(of: process)
            DispatchQueue.main.async {
                if !succeeded { log("The media adapter command `\(command)` failed (\(reason))") }
                finished()
            }
        }
        do {
            try process.run()
        } catch {
            log("Could not run the media adapter command `\(command)`: \(error.localizedDescription)")
            finished()
            return
        }
        Self.readLines(from: errors.fileHandleForReading) { lines in lines.forEach(log) }
    }

    private nonisolated static func outcome(of process: Process) -> (succeeded: Bool, reason: String) {
        let status = process.terminationStatus
        return process.terminationReason == .uncaughtSignal
            ? (false, "signal \(status)")
            : (status == 0, "status \(status)")
    }

    /// Reads `handle` to its end on a background queue and hands complete lines to the main actor in order
    /// (the main queue is FIFO); the line buffer never leaves the reading queue.
    private nonisolated static func readLines(from handle: FileHandle, to receive: @escaping @MainActor ([String]) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            var buffer = LineBuffer()
            var bytes = [UInt8](repeating: 0, count: 64 * 1024)
            // POSIX read returns whatever arrived; `FileHandle.read(upToCount:)` waits for a full chunk or EOF,
            // and `availableData` raises Objective-C exceptions on errors.
            while true {
                let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { break }
                let lines = buffer.append(Data(bytes[..<count]))
                if !lines.isEmpty { DispatchQueue.main.async { receive(lines) } }
            }
            let rest = buffer.finish()
            if !rest.isEmpty { DispatchQueue.main.async { receive(rest) } }
        }
    }
}
