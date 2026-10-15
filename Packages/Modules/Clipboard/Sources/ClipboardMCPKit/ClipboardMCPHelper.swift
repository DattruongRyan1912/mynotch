import Foundation

/// What the agent reads when something is wrong. English, since the agent reads it and tells the user; the setting is named
/// as the user sees it.
public enum ClipboardMCPMessages {
    /// The Settings row that turns the feature on; the app shows the same words.
    public static let settingName = "Cho AI agent đọc lịch sử clipboard (MCP)"

    static let notRunning = "MyNotch is not running, or \"\(settingName)\" is turned off. Ask the user to open MyNotch > Settings > Clipboard and turn it on."
    static let untrusted = "The connection to MyNotch was not used because its folder or socket is not private to your user, so nothing was sent."
    static let noAnswer = "MyNotch did not answer in time. Try again."
    static let tooBig = "query is too long once written out: use at most \(ClipboardMCPLimits.maxQueryLength) characters, with few accents or symbols."
    static let rateLimited = "Too many calls: at most \(ClipboardMCPLimits.maxCallsPerSecond) calls per second. Wait a moment and try again."
}

/// The helper `mynotch-clipboard-mcp`: an MCP server on stdin and stdout that asks the running MyNotch over a Unix socket.
public enum ClipboardMCPHelper {
    /// What a tool call does: checks the arguments, keeps to the rate limit, asks the app and turns its answer into text.
    public final class ToolRunner {
        private let ask: (ClipboardMCPRequest) -> ClipboardMCPClient.Outcome
        private let now: () -> Double
        private var limiter = ClipboardMCPRateLimiter()

        /// - Parameter now: monotonic seconds.
        public init(now: @escaping () -> Double = ToolRunner.uptime, ask: @escaping (ClipboardMCPRequest) -> ClipboardMCPClient.Outcome) {
            self.now = now
            self.ask = ask
        }

        public convenience init(socketPath: String, timeout: TimeInterval = ClipboardMCPClient.defaultTimeout) {
            self.init { ClipboardMCPClient.send($0, socketPath: socketPath, timeout: timeout) }
        }

        public static func uptime() -> Double {
            Double(DispatchTime.now().uptimeNanoseconds) / 1e9
        }

        public func call(_ name: String, _ arguments: [String: JSON]) -> MCPToolResult {
            let request: ClipboardMCPRequest
            do {
                request = try ClipboardMCPRequest.parse(tool: name, arguments: arguments)
            } catch {
                return MCPToolResult(text: error.message, isError: true)
            }
            guard ClipboardMCPWire.requestLine(request) != nil else { return MCPToolResult(text: ClipboardMCPMessages.tooBig, isError: true) }
            // After the arguments, so a call that was wrong does not use up a place of one that is right.
            guard limiter.allow(at: now()) else { return MCPToolResult(text: ClipboardMCPMessages.rateLimited, isError: true) }
            switch ask(request) {
            case .reply(.success(let result)):
                return (try? result.encoded()).map { MCPToolResult(text: String(decoding: $0, as: UTF8.self), isError: false) }
                    ?? MCPToolResult(text: "MyNotch's answer could not be read.", isError: true)
            case .reply(.failure(_, let message)): return MCPToolResult(text: message, isError: true)
            case .unreachable: return MCPToolResult(text: ClipboardMCPMessages.notRunning, isError: true)
            case .untrusted: return MCPToolResult(text: ClipboardMCPMessages.untrusted, isError: true)
            case .noAnswer: return MCPToolResult(text: ClipboardMCPMessages.noAnswer, isError: true)
            }
        }
    }

    /// Serves MCP on `input` and `output` until the input ends.
    public static func run(input: Int32 = STDIN_FILENO, output: Int32 = STDOUT_FILENO, socketPath: String = ClipboardMCPSocket.defaultPath()) {
        let runner = ToolRunner(socketPath: socketPath)
        let session = MCPSession(info: ClipboardMCPTools.serverInfo, tools: ClipboardMCPTools.definitions, callTool: runner.call)
        MCPStdioLoop.run(input: input, output: output, session: session)
    }
}
