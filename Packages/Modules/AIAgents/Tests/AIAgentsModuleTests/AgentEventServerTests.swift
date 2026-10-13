import AgentHookKit
import Foundation
import Testing
@testable import AIAgentsModule

@Suite struct AgentEventServerTests {
    let directory: URL
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() {
        // Unix socket paths are limited to 104 bytes, so the directory is short and outside the sandboxed temp dir.
        directory = URL(filePath: "/tmp/mn-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
    }

    func payload(_ event: String = "Stop") -> HookPayload {
        HookPayload(source: "claude", event: event, sessionID: "s1", timestamp: now)
    }

    /// Waits on the main actor, where the callback runs, until `condition` holds.
    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func aDatagramReachesTheCallbackAndStopRemovesTheSocket() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        var received: [HookPayload] = []
        let server = AgentEventServer(directory: directory) { received.append($0) }
        try server.start()
        #expect(FileManager.default.fileExists(atPath: server.socketPath))
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
        #expect(permissions == 0o700)

        HookDatagramSender.send(try #require(payload("PreToolUse").encodedDatagram()), to: server.socketPath)
        await waitUntil { !received.isEmpty }
        #expect(received == [payload("PreToolUse")])

        server.stop()
        #expect(!FileManager.default.fileExists(atPath: server.socketPath))
    }

    @Test func garbageDatagramsAreIgnored() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        var received: [HookPayload] = []
        let server = AgentEventServer(directory: directory) { received.append($0) }
        try server.start()
        defer { server.stop() }
        HookDatagramSender.send(Data("not json".utf8), to: server.socketPath)
        HookDatagramSender.send(try #require(payload().encodedDatagram()), to: server.socketPath)
        await waitUntil { !received.isEmpty }
        #expect(received == [payload()])
    }

    @Test func aStaleSocketFileIsReplaced() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: directory.appending(path: "agent.sock"))
        var received: [HookPayload] = []
        let server = AgentEventServer(directory: directory) { received.append($0) }
        try server.start()
        defer { server.stop() }
        HookDatagramSender.send(try #require(payload().encodedDatagram()), to: server.socketPath)
        await waitUntil { !received.isEmpty }
        #expect(received.count == 1)
    }

    @Test func aPathThatDoesNotFitIsATypedError() {
        let long = URL(filePath: "/tmp/" + String(repeating: "d", count: 120), directoryHint: .isDirectory)
        let server = AgentEventServer(directory: long) { _ in }
        #expect(throws: AgentEventServer.StartError.pathTooLong) { try server.start() }
        #expect(!FileManager.default.fileExists(atPath: long.path))
    }
}
