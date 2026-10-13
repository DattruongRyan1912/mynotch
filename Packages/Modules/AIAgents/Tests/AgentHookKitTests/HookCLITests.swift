import Foundation
import Testing
@testable import AgentHookKit

@Suite struct HookCLITests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let stopJSON = Data(#"{"hook_event_name":"Stop","session_id":"s1"}"#.utf8)

    func missingSocketPath() -> String { "/tmp/mn-\(UUID().uuidString.prefix(8))/agent.sock" }

    @Test func badArgumentsBadJSONAndAMissingSocketAllExitZero() {
        let path = missingSocketPath()
        #expect(HookCLI.run(arguments: [], stdin: stopJSON, socketPath: path, now: now) == 0)
        #expect(HookCLI.run(arguments: ["--source"], stdin: stopJSON, socketPath: path, now: now) == 0)
        #expect(HookCLI.run(arguments: ["--source", "gemini"], stdin: stopJSON, socketPath: path, now: now) == 0)
        #expect(HookCLI.run(arguments: ["--source", "claude"], stdin: Data("garbage".utf8), socketPath: path, now: now) == 0)
        #expect(HookCLI.run(arguments: ["--source", "claude"], stdin: stopJSON, socketPath: path, now: now) == 0)
        #expect(HookCLI.run(arguments: ["--source", "claude"], stdin: stopJSON, socketPath: String(repeating: "a", count: 300), now: now) == 0)
    }

    @Test func aValidInvocationSendsTheFilteredPayload() throws {
        let directory = "/tmp/mn-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let path = directory + "/agent.sock"
        let receiver = try TestDatagramReceiver(path: path)
        #expect(HookCLI.run(arguments: ["--source", "codex"], stdin: stopJSON, socketPath: path, now: now) == 0)
        let payload = try HookPayload.decode(try #require(receiver.receive()))
        #expect(payload.source == "codex")
        #expect(payload.event == "Stop")
        #expect(payload.sessionID == "s1")
    }
}

/// A bound datagram socket that reads synchronously, standing in for the app.
final class TestDatagramReceiver {
    private let fd: Int32

    init(path: String) throws {
        fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else { throw CocoaError(.fileWriteUnknown) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    deinit { close(fd) }

    func receive() -> Data? {
        var buffer = [UInt8](repeating: 0, count: 4_096)
        let count = recv(fd, &buffer, buffer.count, 0)
        return count > 0 ? Data(buffer[0..<count]) : nil
    }
}
