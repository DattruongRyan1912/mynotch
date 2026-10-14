import AgentHookKit
import Foundation
import Testing
@testable import AIAgentsModule

/// The app's side of the permission socket, with the real helper code (`PermissionClient`) on the other end.
@Suite struct PermissionServerTests {
    let directory: URL
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() {
        // Unix socket paths are limited to 104 bytes, so the directory is short and outside the sandboxed temp dir.
        directory = URL(filePath: "/tmp/mn-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
    }

    var request: HookPayload {
        HookPayload(source: "claude", event: "PermissionRequest", sessionID: "s1", cwd: "/p", tool: "Bash", summary: "ls", timestamp: now)
    }

    final class Tally {
        var value = 0
    }

    /// What reached the callback, on the main actor.
    final class Inbox {
        var requests: [HookPayload] = []
        var connections: [PermissionConnection] = []
        var count: Int { requests.count }
    }

    func server(
        _ inbox: Inbox, requestTimeout: TimeInterval = 30, maxConnections: Int = 32
    ) -> PermissionServer {
        PermissionServer(directory: directory, requestTimeout: requestTimeout, maxConnections: maxConnections) { payload, connection in
            inbox.requests.append(payload)
            inbox.connections.append(connection)
        }
    }

    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    /// The helper's own call, off the main actor, which has to stay free to run the callback.
    func ask(_ payload: HookPayload? = nil, path: String, timeout: TimeInterval = 30) -> Task<PermissionClient.Outcome, Never> {
        let payload = payload ?? request
        return runBlocking { PermissionClient.ask(payload, socketPath: path, timeout: timeout) }
    }

    /// Whether the server closed this client's connection within a moment.
    func isClosedByServer(_ fd: Int32, within seconds: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        var buffer = [UInt8](repeating: 0, count: 64)
        while Date() < deadline {
            var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, 50) > 0 else { continue }
            if read(fd, &buffer, buffer.count) <= 0 { return true }
        }
        return false
    }

    // MARK: Request and answer

    @Test func aRequestReachesTheCallbackAndTheAnswerGoesBackToTheHelper() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = Inbox()
        let server = server(inbox)
        try server.start()
        defer { server.stop() }
        let outcome = ask(path: server.socketPath)
        await waitUntil { inbox.count == 1 }
        #expect(inbox.requests == [request])
        try #require(inbox.connections.first).reply(.allow)
        #expect(await outcome.value == .answered(.allow))
    }

    @Test func eachAnswerReachesTheHelperThatAskedForIt() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = Inbox()
        let server = server(inbox)
        try server.start()
        defer { server.stop() }
        let outcomes = (0..<3).map { _ in ask(path: server.socketPath) }
        await waitUntil { inbox.count == 3 }
        // Answered in the reverse of the order they arrived.
        let answers: [PermissionAnswer] = [.allow, .deny, .ask]
        #expect(inbox.connections.count == 3)
        for (index, connection) in inbox.connections.enumerated() { connection.reply(answers[index]) }
        var received: [PermissionClient.Outcome] = []
        for outcome in outcomes { received.append(await outcome.value) }
        #expect(Set(received.map { "\($0)" }) == Set(answers.map { "\(PermissionClient.Outcome.answered($0))" }))
    }

    @Test func aSecondAnswerIsIgnored() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = Inbox()
        let server = server(inbox)
        try server.start()
        defer { server.stop() }
        let outcome = ask(path: server.socketPath)
        await waitUntil { inbox.count == 1 }
        let connection = try #require(inbox.connections.first)
        connection.reply(.deny)
        connection.reply(.allow)
        #expect(await outcome.value == .answered(.deny))
    }

    // MARK: Who may talk

    @Test func theSocketIsPrivateToTheUserAndRemovedOnStop() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = server(Inbox())
        try server.start()
        #expect(server.socketPath == directory.appending(path: "perm.sock").path)
        #expect(server.socketPath == AgentSocket.permissionPath(besides: directory.appending(path: "agent.sock").path))
        let socketMode = try FileManager.default.attributesOfItem(atPath: server.socketPath)[.posixPermissions] as? Int
        #expect(socketMode == 0o600)
        let directoryMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int
        #expect(directoryMode == 0o700)
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: server.socketPath))
    }

    @Test func onlyTheSameUserIsServed() {
        #expect(PermissionServer.serves(peerUser: geteuid()))
        #expect(!PermissionServer.serves(peerUser: geteuid() &+ 1))
        #expect(!PermissionServer.serves(peerUser: 0 == geteuid() ? 501 : 0))
    }

    @Test(.enabled(if: geteuid() != 0)) func aFolderOfAnotherUserIsRefused() {
        let foreign = URL(filePath: "/Library", directoryHint: .isDirectory)
        let server = PermissionServer(directory: foreign) { _, _ in }
        #expect(throws: AgentEventServer.StartError.directoryNotOwned) { try server.start() }
    }

    @Test func aPathThatDoesNotFitIsATypedError() {
        let long = URL(filePath: "/tmp/" + String(repeating: "d", count: 120), directoryHint: .isDirectory)
        let server = PermissionServer(directory: long) { _, _ in }
        #expect(throws: AgentEventServer.StartError.pathTooLong) { try server.start() }
        #expect(!FileManager.default.fileExists(atPath: long.path))
    }

    @Test func aStaleSocketFileIsReplaced() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: directory.appending(path: "perm.sock"))
        let inbox = Inbox()
        let server = server(inbox)
        try server.start()
        defer { server.stop() }
        let outcome = ask(path: server.socketPath)
        await waitUntil { inbox.count == 1 }
        inbox.connections.first?.reply(.allow)
        #expect(await outcome.value == .answered(.allow))
    }

    // MARK: What is not a request

    @Test func lineThatAreNotPermissionRequestsAreDroppedAndTheirConnectionClosed() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = Inbox()
        let server = server(inbox)
        try server.start()
        defer { server.stop() }
        let preToolUse = HookPayload(source: "claude", event: "PreToolUse", sessionID: "s1", tool: "Bash", timestamp: now)
        let lines: [[UInt8]] = [
            Array("garbage\n".utf8), Array(try #require(PermissionWire.requestLine(preToolUse))), Array("{}\n".utf8),
            Array(#"{"source":"gemini"}"#.utf8) + [0x0A],
        ]
        for line in lines {
            let fd = try connectRaw(to: server.socketPath, send: line)
            defer { close(fd) }
            #expect(isClosedByServer(fd))
        }
        #expect(inbox.count == 0)
    }

    @Test func aRequestThatNeverEndsIsDropped() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = Inbox()
        let server = server(inbox)
        try server.start()
        defer { server.stop() }
        let fd = try connectRaw(to: server.socketPath, send: Array(repeating: UInt8(ascii: "a"), count: PermissionWire.maxRequestLength + 100))
        defer { close(fd) }
        #expect(isClosedByServer(fd))
        #expect(inbox.count == 0)
    }

    @Test func aClientThatSendsNothingIsDroppedWhenItsTimeIsUp() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = Inbox()
        let server = server(inbox, requestTimeout: 0.3)
        try server.start()
        defer { server.stop() }
        let fd = try connectRaw(to: server.socketPath, send: [])
        defer { close(fd) }
        #expect(isClosedByServer(fd))
        #expect(inbox.count == 0)
    }

    @Test func aRequestInPiecesIsAssembled() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = Inbox()
        let server = server(inbox)
        try server.start()
        defer { server.stop() }
        let line = Array(try #require(PermissionWire.requestLine(request)))
        let half = line.count / 2
        let fd = try connectRaw(to: server.socketPath, send: Array(line[..<half]))
        defer { close(fd) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(inbox.count == 0)
        _ = write(fd, Array(line[half...]), line.count - half)
        await waitUntil { inbox.count == 1 }
        #expect(inbox.requests == [request])
    }

    @Test func moreWaitingHelpersThanTheLimitAreRefused() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = Inbox()
        let server = server(inbox, maxConnections: 2)
        try server.start()
        defer { server.stop() }
        let line = Array(try #require(PermissionWire.requestLine(request)))
        let kept = try (0..<2).map { _ in try connectRaw(to: server.socketPath, send: line) }
        // The first is closed below, once: closing a descriptor twice could close another test's socket.
        defer { close(kept[1]) }
        await waitUntil { inbox.count == 2 }
        let extra = try connectRaw(to: server.socketPath, send: line)
        defer { close(extra) }
        #expect(isClosedByServer(extra))
        #expect(inbox.count == 2)
        // A place frees up when a helper leaves.
        close(kept[0])
        await waitUntil { server.connectionCount == 1 }
        let later = try connectRaw(to: server.socketPath, send: line)
        defer { close(later) }
        await waitUntil { inbox.count == 3 }
        #expect(inbox.count == 3)
    }

    // MARK: Going away

    @Test func aHelperThatGivesUpIsReportedToTheHandler() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = Inbox()
        let server = server(inbox)
        try server.start()
        defer { server.stop() }
        let fd = try connectRaw(to: server.socketPath, send: Array(try #require(PermissionWire.requestLine(request))))
        await waitUntil { inbox.count == 1 }
        let gone = Tally()
        try #require(inbox.connections.first).onPeerClosed { gone.value += 1 }
        close(fd)
        await waitUntil { gone.value == 1 }
        #expect(gone.value == 1)
        // Answering a helper that is gone is harmless.
        try #require(inbox.connections.first).reply(.allow)
        await waitUntil { server.connectionCount == 0 }
        #expect(server.connectionCount == 0)
    }

    @Test func aHandlerSetAfterTheHelperLeftIsStillTold() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = Inbox()
        let server = server(inbox)
        try server.start()
        defer { server.stop() }
        let fd = try connectRaw(to: server.socketPath, send: Array(try #require(PermissionWire.requestLine(request))))
        await waitUntil { inbox.count == 1 }
        close(fd)
        await waitUntil { server.connectionCount == 0 }
        let gone = Tally()
        try #require(inbox.connections.first).onPeerClosed { gone.value += 1 }
        await waitUntil { gone.value == 1 }
        #expect(gone.value == 1)
    }

    @Test func stoppingClosesTheHelpersThatWaitWithoutAnAnswer() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = Inbox()
        let server = server(inbox)
        try server.start()
        let outcome = ask(path: server.socketPath)
        await waitUntil { inbox.count == 1 }
        let gone = Tally()
        try #require(inbox.connections.first).onPeerClosed { gone.value += 1 }
        server.stop()
        #expect(await outcome.value == .noAnswer)
        #expect(server.connectionCount == 0)
        // Stopping is the app's own doing, not a helper leaving.
        try await Task.sleep(for: .milliseconds(100))
        #expect(gone.value == 0)
        #expect(!FileManager.default.fileExists(atPath: server.socketPath))
    }

    @Test func requestsQueuedBeforeStopAreDropped() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = Inbox()
        let server = server(inbox)
        try server.start()
        _ = ask(path: server.socketPath)
        // Blocks the main thread, so the request is read and handed to the main queue but not yet delivered.
        usleep(400_000)
        server.stop()
        try await Task.sleep(for: .milliseconds(200))
        #expect(inbox.count == 0)
    }

    @Test func aServerDroppedWithoutStopRemovesItsSocket() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        var path = ""
        do {
            let server = server(Inbox())
            try server.start()
            path = server.socketPath
            #expect(FileManager.default.fileExists(atPath: path))
        }
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}
