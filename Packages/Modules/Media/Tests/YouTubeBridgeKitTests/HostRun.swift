import Foundation
import Synchronization
@testable import YouTubeBridgeKit

/// Runs `YouTubeHostCLI.run` on a thread of its own with a pipe for its stdin, the way Chrome starts the host.
final class HostRun: Sendable {
    /// What the run's thread leaves for the test to read.
    private final class Result: Sendable {
        let code = Mutex<Int32?>(nil)
    }

    private let writeEnd: Int32
    private let result = Result()

    /// The run's exit code once it has ended.
    var exitCode: Int32? { result.code.withLock { $0 } }

    init(
        socketPath: String, reconnectInterval: TimeInterval = 0.05,
        clock: TestClock = TestClock(), expectedOwner: uid_t = geteuid(),
        log: YouTubeBridgeLog = .silent,
        launch: YouTubeHostLaunch = YouTubeHostLaunch(argumentCount: 2, parentName: "Parent")
    ) {
        var fds: [Int32] = [0, 0]
        precondition(pipe(&fds) == 0)
        writeEnd = fds[1]
        let readEnd = fds[0]
        let result = result
        Thread.detachNewThread {
            let code = YouTubeHostCLI.run(
                stdin: FileDescriptorReader(fileDescriptor: readEnd), socketPath: socketPath,
                reconnectInterval: reconnectInterval, now: { clock.now }, expectedOwner: expectedOwner, log: log, launch: launch
            )
            close(readEnd)
            result.code.withLock { $0 = code }
        }
    }

    /// One native messaging frame, as Chrome writes it.
    func send(_ message: Data) {
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

    /// Closes the input like Chrome does when the extension disconnects, and returns the exit code (nil if it hangs).
    func finish() async -> Int32? {
        close(writeEnd)
        await waitUntil { exitCode != nil }
        return exitCode
    }
}
