import Foundation

/// Reads messages from one descriptor and writes the answers to another, which is stdin and stdout for a server a client
/// starts. Nothing but responses is ever written to `output`: the spec forbids anything else on stdout.
public enum MCPStdioLoop {
    /// A message is a few hundred bytes; a line far longer is not one.
    public static let maxLineLength = 1 << 20

    /// Returns when the input ends (the client closed it, which is how a stdio server is told to stop) or the output is gone.
    public static func run(input: Int32, output: Int32, session: MCPSession) {
        var framer = MCPLineFramer(maxLength: maxLineLength)
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(input, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            // A descriptor that is not blocking has nothing yet: wait for it, so this does not spin.
            if count < 0, errno == EAGAIN {
                waitForever(on: input, events: Int32(POLLIN))
                continue
            }
            let lines = count > 0 ? framer.append(Data(buffer[0..<count])) : framer.finish()
            for line in lines {
                let answer: Data? = switch line {
                case .message(let data): session.handle(data)
                case .oversized: MCPSession.errorLine(code: -32600, message: "Invalid Request: the message is too large")
                }
                if let answer, !write(answer + Data("\n".utf8), to: output) { return }
            }
            if count <= 0 { return }
        }
    }

    private static func write(_ data: Data, to descriptor: Int32) -> Bool {
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { Foundation.write(descriptor, $0.baseAddress! + offset, data.count - offset) }
            if written > 0 {
                offset += written
            } else if written < 0, errno == EINTR {
                continue
            } else if written < 0, errno == EAGAIN {
                waitForever(on: descriptor, events: Int32(POLLOUT))
            } else {
                return false
            }
        }
        return true
    }

    private static func waitForever(on descriptor: Int32, events: Int32) {
        var poller = pollfd(fd: descriptor, events: Int16(events), revents: 0)
        _ = poll(&poller, 1, -1)
    }
}
