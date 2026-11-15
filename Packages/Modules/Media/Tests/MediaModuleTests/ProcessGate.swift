import Darwin
import Foundation

/// A named pipe that a fake adapter script blocks on (`gate.wait` in the script) until the test lets it through, one
/// token at a time. The script needs no polling loop, which would start a process every few milliseconds, and the
/// test, not the clock, decides when each one goes on.
final class ProcessGate {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    let path: String
    private let descriptor: Int32

    init(in directory: URL, name: String = "gate") throws {
        path = directory.appending(path: name).path
        guard mkfifo(path, 0o600) == 0 else { throw Failure(description: "mkfifo failed (errno \(errno))") }
        // Read and write: the pipe keeps its tokens while no script has it open, and opening it never blocks.
        descriptor = Darwin.open(path, O_RDWR)
        guard descriptor >= 0 else { throw Failure(description: "open failed (errno \(errno))") }
    }

    deinit {
        // A script still waiting sees the end of the pipe and goes on, so a failed test leaves no process blocked.
        close(descriptor)
    }

    /// The shell line that waits for one token.
    var wait: String { "read -r _ < '\(path)'" }

    /// Lets `count` scripts through: the ones waiting now, or the next to wait.
    func open(_ count: Int = 1) {
        let tokens = [UInt8](repeating: UInt8(ascii: "\n"), count: count)
        _ = write(descriptor, tokens, tokens.count)
    }
}
