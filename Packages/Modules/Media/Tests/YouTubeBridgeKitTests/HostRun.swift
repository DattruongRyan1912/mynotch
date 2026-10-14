import Foundation
import Synchronization
@testable import YouTubeBridgeKit

/// Reads like `base` but hands each piece over `delay` seconds after it arrived: a host thread that is slow to run.
struct LateReader: ByteReading {
    var base: FileDescriptorReader
    var delay: TimeInterval

    func read(upTo count: Int) -> Data {
        let data = base.read(upTo: count)
        if delay > 0, !data.isEmpty { Thread.sleep(forTimeInterval: delay) }
        return data
    }
}

/// Runs `YouTubeHostCLI.run` on a thread of its own with a pipe for its stdin, the way Chrome starts the host.
final class HostRun: Sendable {
    /// What the run's thread leaves for the test to read, and what the test counts.
    private final class Progress: Sendable {
        let code = Mutex<Int32?>(nil)
        /// Messages the test has written and messages the host has dealt with.
        let sent = Mutex(0)
        let handled = Mutex(0)
        let recorder = LogRecorder()
    }

    private let writeEnd: Int32
    private let progress = Progress()

    /// The run's exit code once it has ended.
    var exitCode: Int32? { progress.code.withLock { $0 } }

    /// Everything the host has logged so far, whether or not the test passed a sink of its own.
    var logLines: [String] { progress.recorder.lines }

    init(
        socketPath: String, reconnectInterval: TimeInterval = 0.05,
        clock: TestClock = TestClock(), expectedOwner: uid_t = geteuid(),
        readDelay: TimeInterval = 0,
        log: YouTubeBridgeLog = .silent,
        launch: YouTubeHostLaunch = YouTubeHostLaunch(argumentCount: 2, parentName: "Parent")
    ) {
        var fds: [Int32] = [0, 0]
        precondition(pipe(&fds) == 0)
        writeEnd = fds[1]
        let readEnd = fds[0]
        let progress = progress
        let both = YouTubeBridgeLog { line in
            progress.recorder.log(line)
            log(line)
        }
        Thread.detachNewThread {
            let code = YouTubeHostCLI.run(
                stdin: LateReader(base: FileDescriptorReader(fileDescriptor: readEnd), delay: readDelay), socketPath: socketPath,
                reconnectInterval: reconnectInterval, now: { clock.now }, expectedOwner: expectedOwner, log: both, launch: launch,
                didHandle: { progress.handled.withLock { $0 += 1 } }
            )
            close(readEnd)
            progress.code.withLock { $0 = code }
        }
    }

    /// One native messaging frame, as Chrome writes it.
    func send(_ message: Data) {
        progress.sent.withLock { $0 += 1 }
        writeRaw(nativeFrame(message))
    }

    /// Bytes as they are, for a stream that is not well formed.
    func writeRaw(_ frame: Data) {
        frame.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = write(writeEnd, bytes.baseAddress! + offset, bytes.count - offset)
                if written <= 0 { return }
                offset += written
            }
        }
    }

    @discardableResult
    func sendJSON(_ object: Any) -> Data {
        let data = YouTubeMessageTests.data(object)
        send(data)
        return data
    }

    /// Waits until the host has dealt with every message written so far. What a test needs to know before it changes the
    /// world the host sees (starts or stops the app, moves the clock): a message written to the pipe may still be unread.
    @discardableResult
    func waitUntilHandled() async -> Bool {
        await waitUntil { progress.handled.withLock { $0 } == progress.sent.withLock { $0 } }
    }

    /// Waits until the host has logged a line that contains `fragment`.
    @discardableResult
    func waitForLog(containing fragment: String) async -> Bool {
        await waitUntil { logLines.contains { $0.contains(fragment) } }
    }

    /// Closes the input like Chrome does when the extension disconnects, and returns the exit code (nil if it hangs).
    func finish() async -> Int32? {
        close(writeEnd)
        await waitUntil { exitCode != nil }
        return exitCode
    }
}
