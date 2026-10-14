import AgentHookKit
import Foundation
import Synchronization
import Testing
@testable import AIAgentsModule

/// One connection on a socket pair: the helper's end is the test's, so what each side does and when is exact.
@Suite struct PermissionConnectionTests {
    let queue = DispatchQueue(label: "PermissionConnectionTests")
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    final class Recorder: Sendable {
        let delivered = Mutex<[HookPayload]>([])
        let ended = Mutex(0)
    }

    /// The connection and the helper's end of the pipe. The test closes `helper` itself, or leaves it to `defer`.
    func makePair(_ recorder: Recorder, timeout: TimeInterval = 5) throws -> (connection: PermissionConnection, helper: Int32) {
        var fds: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0, fcntl(fds[0], F_SETFL, O_NONBLOCK) == 0 else { throw CocoaError(.fileReadUnknown) }
        var enable: Int32 = 1
        setsockopt(fds[0], SOL_SOCKET, SO_NOSIGPIPE, &enable, socklen_t(MemoryLayout<Int32>.size))
        let connection = PermissionConnection(fd: fds[0], queue: queue) { _ in recorder.ended.withLock { $0 += 1 } }
        connection.begin(timeout: timeout) { payload in recorder.delivered.withLock { $0.append(payload) } }
        return (connection, fds[1])
    }

    func send(_ helper: Int32) throws {
        let payload = HookPayload(source: "claude", event: "PermissionRequest", sessionID: "s1", tool: "Bash", summary: "ls", timestamp: now)
        let line = Array(try #require(PermissionWire.requestLine(payload)))
        #expect(write(helper, line, line.count) == line.count)
    }

    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    /// What the helper reads until the connection closes.
    func readToEnd(_ helper: Int32) -> String {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 256)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            var poller = pollfd(fd: helper, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, 50) > 0 else { continue }
            let count = read(helper, &buffer, buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer[0..<count])
        }
        return String(decoding: data, as: UTF8.self)
    }

    @Test func theAnswerIsWrittenOnceAndTheConnectionEndsOnce() async throws {
        let recorder = Recorder()
        let (connection, helper) = try makePair(recorder)
        defer { close(helper) }
        try send(helper)
        await waitUntil { recorder.delivered.withLock { $0.count } == 1 }
        connection.reply(.allow)
        connection.reply(.deny)
        #expect(readToEnd(helper) == "{\"decision\":\"allow\"}\n")
        #expect(recorder.ended.withLock { $0 } == 1)
    }

    @Test func nothingIsWrittenAfterTheAppShutDownTheConnection() async throws {
        let recorder = Recorder()
        let (connection, helper) = try makePair(recorder)
        defer { close(helper) }
        try send(helper)
        await waitUntil { recorder.delivered.withLock { $0.count } == 1 }
        connection.shutDown()
        connection.reply(.allow)
        #expect(readToEnd(helper).isEmpty)
    }

    @Test func shuttingDownAfterTheAnswerDoesNotCloseTheSocketAgain() async throws {
        let recorder = Recorder()
        let (connection, helper) = try makePair(recorder)
        defer { close(helper) }
        try send(helper)
        await waitUntil { recorder.delivered.withLock { $0.count } == 1 }
        connection.reply(.deny)
        connection.shutDown()
        connection.shutDown()
        #expect(readToEnd(helper) == "{\"decision\":\"deny\"}\n")
    }

    @Test func aHelperThatLeavesBeforeTheAnswerEndsTheConnectionAndAnAnswerIsHarmless() async throws {
        let recorder = Recorder()
        let (connection, helper) = try makePair(recorder)
        try send(helper)
        await waitUntil { recorder.delivered.withLock { $0.count } == 1 }
        close(helper)
        await waitUntil { recorder.ended.withLock { $0 } == 1 }
        connection.reply(.allow)
        connection.shutDown()
        try await Task.sleep(for: .milliseconds(50))
        #expect(recorder.ended.withLock { $0 } == 1)
    }

    @Test func aHelperThatLeavesBeforeItsRequestIsCompleteIsNeverDelivered() async throws {
        let recorder = Recorder()
        let (_, helper) = try makePair(recorder)
        let part = Array("{\"source\":\"claude\"".utf8)
        _ = write(helper, part, part.count)
        close(helper)
        await waitUntil { recorder.ended.withLock { $0 } == 1 }
        #expect(recorder.ended.withLock { $0 } == 1)
        #expect(recorder.delivered.withLock { $0.isEmpty })
    }
}
