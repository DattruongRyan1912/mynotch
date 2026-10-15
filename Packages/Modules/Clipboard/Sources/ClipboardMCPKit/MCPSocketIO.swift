import Foundation

/// A point in time on the monotonic clock, which a wait never passes.
public struct MCPDeadline: Sendable {
    private let end: UInt64

    public init(after seconds: TimeInterval) {
        end = DispatchTime.now().uptimeNanoseconds + UInt64(max(seconds, 0) * 1e9)
    }

    /// Milliseconds left, rounded up; 0 once it has passed.
    var remainingMilliseconds: Int32 {
        let now = DispatchTime.now().uptimeNanoseconds
        guard end > now else { return 0 }
        return Int32(min((end - now + 999_999) / 1_000_000, UInt64(Int32.max)))
    }
}

/// Lines over a non-blocking stream socket, each wait bounded by a deadline.
public enum MCPSocketIO {
    public enum Line: Equatable, Sendable {
        /// A line, without its newline.
        case line(Data)
        /// The peer closed first, after these bytes, which are not a whole line.
        case endOfStream(Data)
        case timedOut
        /// More than the limit came without a newline.
        case tooLong
        case failed
    }

    /// True when the poll says `events` can proceed before the deadline.
    static func wait(for events: Int32, on descriptor: Int32, until deadline: MCPDeadline) -> Bool {
        while true {
            let remaining = deadline.remainingMilliseconds
            guard remaining > 0 else { return false }
            var poller = pollfd(fd: descriptor, events: Int16(events), revents: 0)
            let ready = poll(&poller, 1, remaining)
            if ready > 0 { return true }
            if ready == 0 || errno != EINTR { return false }
        }
    }

    public static func readLine(from descriptor: Int32, maxLength: Int, until deadline: MCPDeadline) -> Line {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            guard wait(for: Int32(POLLIN), on: descriptor, until: deadline) else { return .timedOut }
            let count = read(descriptor, &buffer, buffer.count)
            if count < 0 {
                if errno == EAGAIN || errno == EINTR { continue }
                return .failed
            }
            if count == 0 { return .endOfStream(data) }
            if let newline = buffer[0..<count].firstIndex(of: UInt8(ascii: "\n")) {
                data.append(contentsOf: buffer[0..<newline])
                return data.count > maxLength ? .tooLong : .line(data)
            }
            data.append(contentsOf: buffer[0..<count])
            if data.count > maxLength { return .tooLong }
        }
    }

    public static func writeAll(_ data: Data, to descriptor: Int32, until deadline: MCPDeadline) -> Bool {
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { write(descriptor, $0.baseAddress! + offset, data.count - offset) }
            if written > 0 {
                offset += written
            } else if written < 0, errno == EAGAIN || errno == EINTR {
                guard wait(for: Int32(POLLOUT), on: descriptor, until: deadline) else { return false }
            } else {
                return false
            }
        }
        return true
    }
}
