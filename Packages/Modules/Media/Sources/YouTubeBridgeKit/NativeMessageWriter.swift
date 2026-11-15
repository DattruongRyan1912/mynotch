import Foundation
import Synchronization

/// Where bytes go: a pipe, or a collector in a test.
public protocol ByteWriting: Sendable {
    /// All of `data`, or false when it could not be written (the other end of a pipe is gone).
    func write(_ data: Data) -> Bool
}

/// A file descriptor written with `write(2)`. Whole messages are written one at a time, so two threads never interleave theirs.
public final class FileDescriptorWriter: ByteWriting {
    public let fileDescriptor: Int32
    private let lock = Mutex(())

    public init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
        // A write to a pipe whose reader is gone must fail instead of ending the process with SIGPIPE.
        _ = fcntl(fileDescriptor, F_SETNOSIGPIPE, 1)
    }

    public func write(_ data: Data) -> Bool {
        lock.withLock { _ in
            data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let written = Foundation.write(fileDescriptor, bytes.baseAddress! + offset, bytes.count - offset)
                    if written > 0 {
                        offset += written
                    } else if written < 0, errno == EINTR {
                        continue
                    } else {
                        return false
                    }
                }
                return true
            }
        }
    }
}

/// What Chrome reads from a native host's stdout: each message is a 4-byte length in the machine's byte order, then that many
/// bytes of JSON (the other direction of `NativeMessageReader`).
public enum NativeMessage {
    public static func frame(_ payload: Data) -> Data {
        withUnsafeBytes(of: UInt32(payload.count)) { Data($0) } + payload
    }
}
