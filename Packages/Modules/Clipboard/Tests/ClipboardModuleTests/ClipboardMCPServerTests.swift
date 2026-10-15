import ClipboardMCPKit
import Foundation
import Synchronization
import Testing
@testable import ClipboardModule

/// The app's end of the socket, driven by the real helper client over real sockets.
@Suite struct ClipboardMCPServerTests {
    /// A folder under /tmp, short so the socket path fits, that is removed with the test.
    final class Folder {
        let directory = URL(filePath: "/tmp/mn-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
        var socketPath: String { directory.appending(path: "mcp.sock").path }

        deinit { try? FileManager.default.removeItem(at: directory) }
    }

    final class Seen: @unchecked Sendable {
        var lines: [Data] = []
        var onMainThread: [Bool] = []
    }

    let folder = Folder()
    let seen = Seen()
    let request = ClipboardMCPRequest.search(ClipboardMCPSearch(query: "invoice"))
    let answer = ClipboardMCPWireReply.success(.object(["count": .int(0), "items": .array([])]))

    func makeServer(timeout: TimeInterval = 5, maxConnections: Int = 8, trustedUser: uid_t = geteuid()) -> ClipboardMCPServer {
        let seen = seen
        let answer = answer
        return ClipboardMCPServer(socketPath: folder.socketPath, requestTimeout: timeout, maxConnections: maxConnections, trustedUser: trustedUser) { line in
            seen.lines.append(line)
            seen.onMainThread.append(Thread.isMainThread)
            return answer
        }
    }

    /// Runs `work`, which blocks, on a thread of its own: the pool that `async` code runs on has few threads, and tests that wait
    /// for sockets must not use them up.
    func onAThread<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: work()) }
        }
    }

    func ask(_ path: String? = nil, timeout: TimeInterval = 60) async -> ClipboardMCPClient.Outcome {
        let path = path ?? folder.socketPath
        let request = request
        return await onAThread { ClipboardMCPClient.send(request, socketPath: path, timeout: timeout) }
    }

    /// Connects without the client: raw bytes, to see what the server does with them.
    func connectRaw() -> Int32? {
        guard let address = MCPSocketAddress(path: folder.socketPath) else { return nil }
        signal(SIGPIPE, SIG_IGN)
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        var target = address.value
        let connected = withUnsafePointer(to: &target) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    /// Everything the server sends until it closes the connection, or until `seconds` pass (then nil).
    func readUntilClosed(_ descriptor: Int32, seconds: Double = 60) async -> Data? {
        await onAThread {
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1_024)
            let end = Date().addingTimeInterval(seconds)
            while true {
                var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                let left = Int32(max(end.timeIntervalSinceNow, 0) * 1000)
                guard poll(&poller, 1, left) > 0 else { return nil }
                let count = read(descriptor, &buffer, buffer.count)
                if count <= 0 { return data }
                data.append(contentsOf: buffer[0..<count])
            }
        }
    }

    /// The handler runs on the main actor, which other tests keep busy: a generous wait costs nothing when it is free.
    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<3_000 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    func mode(of path: String) -> Int {
        var info = stat()
        return stat(path, &info) == 0 ? Int(info.st_mode & 0o777) : -1
    }

    // MARK: A round trip

    @Test func theHelperAsksAndTheHandlerAnswersOnTheMainThread() async throws {
        let server = makeServer()
        try server.start()
        #expect(await ask() == .reply(answer))
        #expect(seen.lines.count == 1)
        #expect(ClipboardMCPWire.decodeRequest(seen.lines[0]) == .request(request))
        #expect(seen.onMainThread == [true])
        server.stop()
    }

    @Test func manyCallsOneAfterAnotherAreEachAnswered() async throws {
        let server = makeServer()
        try server.start()
        for _ in 0..<30 { #expect(await ask() == .reply(answer)) }
        #expect(seen.lines.count == 30)
        server.stop()
    }

    @Test func severalHelpersAtOnceAreEachAnswered() async throws {
        let server = makeServer()
        try server.start()
        let path = folder.socketPath
        let request = request
        let outcomes = Mutex<[ClipboardMCPClient.Outcome]>([])
        for _ in 0..<6 {
            DispatchQueue.global().async {
                let outcome = ClipboardMCPClient.send(request, socketPath: path, timeout: 60)
                outcomes.withLock { $0.append(outcome) }
            }
        }
        await waitUntil { outcomes.withLock { $0.count } == 6 }
        #expect(outcomes.withLock { $0 } == Array(repeating: .reply(answer), count: 6))
        server.stop()
    }

    // MARK: Who may connect

    @Test func theSocketIsPrivateAndWhatTheAppMakesIsWhatTheHelperTrusts() throws {
        // The folder exists, open to everyone, as `/tmp/mynotch-<uid>` could be: the server closes it.
        try FileManager.default.createDirectory(at: folder.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o777])
        chmod(folder.directory.path, 0o777)
        let server = makeServer()
        try server.start()
        #expect(mode(of: folder.socketPath) == 0o600)
        #expect(mode(of: folder.directory.path) == 0o700)
        #expect(MCPSocketTrust.inspect(socketPath: folder.socketPath) == .trusted)
        server.stop()
    }

    @Test func aFolderOfAnotherUserIsNotUsed() throws {
        try FileManager.default.createDirectory(at: folder.directory, withIntermediateDirectories: true)
        // The test cannot make a folder of another user; it starts the server as that user would, which is the same check.
        let server = makeServer(trustedUser: geteuid() &+ 1)
        #expect(throws: ClipboardMCPServer.StartError.directoryNotOwned) { try server.start() }
        #expect(!server.isListening)
    }

    @Test func aLinkInPlaceOfTheFolderIsNotUsed() throws {
        let target = Folder()
        try FileManager.default.createDirectory(at: target.directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: folder.directory.path, withDestinationPath: target.directory.path)
        let server = makeServer()
        #expect(throws: ClipboardMCPServer.StartError.directoryNotOwned) { try server.start() }
    }

    @Test func onlyTheUsersOwnProcessesAreServed() {
        #expect(ClipboardMCPServer.serves(peerUser: geteuid(), trustedUser: geteuid()))
        #expect(!ClipboardMCPServer.serves(peerUser: geteuid() &+ 1, trustedUser: geteuid()))
    }

    @Test func aPeerOfAnotherUserIsDroppedBeforeItIsHeard() async throws {
        // The server believes the user it serves is somebody else, so the real helper, which is this user, is the stranger.
        let seen = seen
        let answer = answer
        let server = ClipboardMCPServer(socketPath: folder.socketPath, trustedUser: geteuid(), servedUser: geteuid() &+ 1) { line in
            seen.lines.append(line)
            return answer
        }
        try server.start()
        let descriptor = try #require(connectRaw())
        defer { close(descriptor) }
        let line = ClipboardMCPWire.requestLine(request) ?? Data()
        _ = line.withUnsafeBytes { write(descriptor, $0.baseAddress, line.count) }
        #expect(await readUntilClosed(descriptor) == Data())
        #expect(seen.lines.isEmpty)
        server.stop()
    }

    // MARK: What it does with bad input

    @Test func aLineIsPassedOnAsItIsAndTheHandlerDecidesWhatItMeans() async throws {
        let server = makeServer()
        try server.start()
        let descriptor = try #require(connectRaw())
        defer { close(descriptor) }
        let bytes = Array("garbage\n".utf8)
        _ = write(descriptor, bytes, bytes.count)
        let reply = try #require(await readUntilClosed(descriptor))
        #expect(seen.lines == [Data("garbage".utf8)])
        #expect(ClipboardMCPWire.decodeReply(reply.dropLast()) == answer)
        server.stop()
    }

    @Test func aRequestOverTheLimitIsDroppedAtOnce() async throws {
        let server = makeServer()
        try server.start()
        let descriptor = try #require(connectRaw())
        defer { close(descriptor) }
        let bytes = [UInt8](repeating: UInt8(ascii: "a"), count: ClipboardMCPWire.maxRequestLength + 100)
        _ = write(descriptor, bytes, bytes.count)
        let reply = await readUntilClosed(descriptor)
        #expect(reply == Data())
        #expect(seen.lines.isEmpty)
        server.stop()
    }

    @Test func aHelperThatSendsNothingIsDroppedAfterTheTimeout() async throws {
        let server = makeServer(timeout: 0.3)
        try server.start()
        let descriptor = try #require(connectRaw())
        defer { close(descriptor) }
        #expect(await readUntilClosed(descriptor, seconds: 8) == Data())
        #expect(seen.lines.isEmpty)
        server.stop()
    }

    @Test func aRequestThatStopsHalfWayIsDroppedAfterTheTimeout() async throws {
        let server = makeServer(timeout: 0.3)
        try server.start()
        let descriptor = try #require(connectRaw())
        defer { close(descriptor) }
        let bytes = Array(#"{"arguments":{"query""#.utf8)
        _ = write(descriptor, bytes, bytes.count)
        #expect(await readUntilClosed(descriptor, seconds: 8) == Data())
        #expect(seen.lines.isEmpty)
        server.stop()
    }

    @Test func aHelperThatLeavesBeforeItsRequestIsCompleteIsForgotten() async throws {
        let server = makeServer()
        try server.start()
        let descriptor = try #require(connectRaw())
        close(descriptor)
        await waitUntil { server.connectionCount == 0 }
        #expect(server.connectionCount == 0)
        #expect(await ask() == .reply(answer))
        server.stop()
    }

    @Test func helpersOverTheLimitAreRefusedAndTheOnesWaitingAreNotDisturbed() async throws {
        let server = makeServer(timeout: 30, maxConnections: 2)
        try server.start()
        let first = try #require(connectRaw())
        let second = try #require(connectRaw())
        defer { close(first); close(second) }
        await waitUntil { server.connectionCount == 2 }
        let third = try #require(connectRaw())
        defer { close(third) }
        #expect(await readUntilClosed(third) == Data())
        #expect(server.connectionCount == 2)
        server.stop()
    }

    // MARK: Starting and stopping

    @Test func stoppingClosesTheSocketAndRemovesTheFile() async throws {
        let server = makeServer()
        try server.start()
        #expect(server.isListening)
        server.stop()
        #expect(!server.isListening)
        #expect(!FileManager.default.fileExists(atPath: folder.socketPath))
        #expect(await ask() == .unreachable)
        server.stop()
    }

    @Test func startingAgainReplacesAFileALastRunLeftBehind() async throws {
        try FileManager.default.createDirectory(at: folder.directory, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: URL(filePath: folder.socketPath))
        let server = makeServer()
        try server.start()
        #expect(await ask() == .reply(answer))
        server.stop()
        try server.start()
        #expect(await ask() == .reply(answer))
        server.stop()
    }

    @Test func aRequestThatWaitsForTheMainThreadWhenTheServerStopsIsNotAnswered() async throws {
        let server = makeServer()
        try server.start()
        let path = folder.socketPath
        let request = request
        let pending = Mutex<ClipboardMCPClient.Outcome?>(nil)
        DispatchQueue.global().async {
            let outcome = ClipboardMCPClient.send(request, socketPath: path, timeout: 60)
            pending.withLock { $0 = outcome }
        }
        // The main thread is held, so the request is read and queued for it, and cannot run before the server stops.
        let start = DispatchTime.now().uptimeNanoseconds
        while server.requestsRead == 0, DispatchTime.now().uptimeNanoseconds - start < 8_000_000_000 { usleep(2_000) }
        #expect(server.requestsRead == 1)
        server.stop()
        await waitUntil { pending.withLock { $0 } != nil }
        #expect(pending.withLock { $0 } == .noAnswer)
        #expect(seen.lines.isEmpty)
    }

    @Test func aPathThatDoesNotFitIsAnError() {
        let server = ClipboardMCPServer(socketPath: "/tmp/" + String(repeating: "d", count: 120) + "/mcp.sock") { _ in .failure(.failed, "") }
        #expect(throws: ClipboardMCPServer.StartError.pathTooLong) { try server.start() }
    }
}
