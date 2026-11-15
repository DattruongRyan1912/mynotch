import Foundation
import Testing
@testable import ClipboardMCPKit

/// The loop that reads messages from one descriptor and writes the answers to another, on real pipes.
@Suite struct MCPStdioLoopTests {
    private struct Pipe {
        var read: Int32 = 0
        var write: Int32 = 0

        init() {
            var fds: [Int32] = [0, 0]
            precondition(pipe(&fds) == 0)
            read = fds[0]
            write = fds[1]
        }
    }

    /// Runs the loop on `input` (then end of input) and returns what it wrote, as lines.
    private func run(_ chunks: [Data]) async -> [String] {
        let input = Pipe()
        let output = Pipe()
        let session = MCPSession(
            info: MCPServerInfo(name: "demo", title: "Demo", version: "1", instructions: nil), tools: ClipboardMCPTools.definitions
        ) { _, _ in MCPToolResult(text: "ok", isError: false) }
        let loop = Task.detached { MCPStdioLoop.run(input: input.read, output: output.write, session: session) }
        for chunk in chunks {
            chunk.withUnsafeBytes { _ = write(input.write, $0.baseAddress, chunk.count) }
        }
        close(input.write)
        await loop.value
        close(output.write)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(output.read, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer[0..<count])
        }
        close(input.read)
        close(output.read)
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    private func line(_ text: String) -> Data { Data((text + "\n").utf8) }

    @Test func eachMessageGetsOneLineAnswerInOrder() async throws {
        let lines = await run([
            line(#"{"jsonrpc":"2.0","id":1,"method":"ping"}"#),
            line(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#),
            line(#"{"jsonrpc":"2.0","id":2,"method":"ping"}"#),
        ])
        #expect(lines.count == 2)
        #expect(try JSON(decoding: Data(lines[0].utf8))["id"] == .int(1))
        #expect(try JSON(decoding: Data(lines[1].utf8))["id"] == .int(2))
    }

    @Test func aMessageInPiecesIsAnsweredOnceWhenItIsWhole() async throws {
        let text = #"{"jsonrpc":"2.0","id":7,"method":"ping"}"# + "\n"
        let bytes = Array(text.utf8)
        let lines = await run([Data(bytes[0..<5]), Data(bytes[5..<20]), Data(bytes[20...])])
        #expect(lines.count == 1)
        #expect(try JSON(decoding: Data(lines[0].utf8))["id"] == .int(7))
    }

    @Test func garbageGetsAParseErrorAndTheLoopGoesOn() async throws {
        let lines = await run([line("garbage"), line(#"{"jsonrpc":"2.0","id":3,"method":"ping"}"#)])
        #expect(lines.count == 2)
        #expect(try JSON(decoding: Data(lines[0].utf8))["error"]?["code"] == .int(-32700))
        #expect(try JSON(decoding: Data(lines[1].utf8))["result"] != nil)
    }

    @Test func aLineOverTheLimitGetsAnInvalidRequestAndTheLoopGoesOn() async throws {
        let huge = Data(repeating: UInt8(ascii: "a"), count: MCPStdioLoop.maxLineLength + 10) + Data("\n".utf8)
        let lines = await run([huge, line(#"{"jsonrpc":"2.0","id":3,"method":"ping"}"#)])
        #expect(lines.count == 2)
        #expect(try JSON(decoding: Data(lines[0].utf8))["error"]?["code"] == .int(-32600))
        #expect(try JSON(decoding: Data(lines[1].utf8))["id"] == .int(3))
    }

    @Test func aLastMessageWithoutANewlineIsStillAnswered() async throws {
        let lines = await run([Data(#"{"jsonrpc":"2.0","id":5,"method":"ping"}"#.utf8)])
        #expect(lines.count == 1)
    }

    @Test func endOfInputEndsTheLoop() async {
        let lines = await run([])
        #expect(lines.isEmpty)
    }

    @Test func anInputThatIsNotBlockingIsWaitedForAndNotTakenForTheEnd() async throws {
        let input = Pipe()
        let output = Pipe()
        #expect(fcntl(input.read, F_SETFL, O_NONBLOCK) == 0)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                let session = MCPSession(
                    info: MCPServerInfo(name: "demo", title: "Demo", version: "1", instructions: nil), tools: ClipboardMCPTools.definitions
                ) { _, _ in MCPToolResult(text: "ok", isError: false) }
                MCPStdioLoop.run(input: input.read, output: output.write, session: session)
                done.resume()
            }
            // The loop has found nothing to read by now; a loop that took that for the end would already be gone.
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(300)) {
                let message = Data((#"{"jsonrpc":"2.0","id":9,"method":"ping"}"# + "\n").utf8)
                message.withUnsafeBytes { _ = write(input.write, $0.baseAddress, message.count) }
                close(input.write)
            }
        }
        close(output.write)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(output.read, &buffer, buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer[0..<count])
        }
        close(input.read)
        close(output.read)
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        #expect(lines.count == 1)
        #expect(try JSON(decoding: Data(lines[0].utf8))["id"] == .int(9))
    }
}
