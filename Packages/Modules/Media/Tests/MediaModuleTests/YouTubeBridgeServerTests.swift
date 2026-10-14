import Foundation
import Synchronization
import Testing
@testable import MediaModule
@testable import YouTubeBridgeKit

/// A client of the app's socket, as the host is: connects, writes bytes.
final class YouTubeTestClient {
    let fd: Int32

    init?(path: String) {
        guard let fd = UnixStreamSocket.connect(to: path, expectedOwner: geteuid()) else { return nil }
        self.fd = fd
    }

    deinit { close(fd) }

    @discardableResult
    func send(_ bytes: Data) -> Bool { UnixStreamSocket.writeAll(bytes, to: fd) }

    @discardableResult
    func sendFrame(_ json: Data) -> Bool { send(AppFrame.encode(json)!) }

    /// The server closed this connection.
    var isClosedByServer: Bool { UnixStreamSocket.peerHasClosed(fd) }
}

/// Waits on the main actor, where the callbacks run, until `condition` holds.
@discardableResult
func waitUntil(seconds: Double = 5, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() {
        if Date() > deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

/// Set by a thread that ends, for a test to wait on.
final class Finished: Sendable {
    let flag = Mutex(false)
}

@Suite final class YouTubeBridgeServerTests {
    /// Unix socket paths are limited to 104 bytes, so the folder is short and outside the sandboxed temp dir.
    let directory = URL(filePath: "/tmp/mn-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
    var path: String { directory.appending(path: "youtube.sock").path }
    var received: [YouTubeMessage] = []

    deinit { try? FileManager.default.removeItem(at: directory) }

    func makeServer() -> YouTubeBridgeServer {
        YouTubeBridgeServer(socketPath: path) { [unowned self] in received.append($0) }
    }

    // MARK: receiving

    @Test func framesFromAClientReachTheCallbackInOrderAsMessages() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let client = try #require(YouTubeTestClient(path: path))
        let sent = [YouTubeTestMessages.captions(), YouTubeTestMessages.playback(), YouTubeTestMessages.clear()]
        for message in sent { client.sendFrame(YouTubeTestMessages.json(message)) }
        await waitUntil { received.count == 3 }
        #expect(received == sent)
    }

    @Test func theSocketIsPrivateToTheUser() throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        #expect(try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int == 0o600)
        #expect(try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int == 0o700)
    }

    @Test func aFrameThatArrivesInPiecesIsDelivered() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let client = try #require(YouTubeTestClient(path: path))
        let frame = AppFrame.encode(YouTubeTestMessages.json(YouTubeTestMessages.captions()))!
        for start in stride(from: 0, to: frame.count, by: 7) {
            client.send(frame[start..<min(start + 7, frame.count)])
            try await Task.sleep(for: .milliseconds(2))
        }
        await waitUntil { !received.isEmpty }
        #expect(received == [YouTubeTestMessages.captions()])
    }

    @Test func manyFramesInOneWriteAreAllDelivered() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let client = try #require(YouTubeTestClient(path: path))
        var burst = Data()
        for index in 0..<50 { burst += AppFrame.encode(YouTubeTestMessages.json(YouTubeTestMessages.playback(time: Double(index))))! }
        client.send(burst)
        await waitUntil { received.count == 50 }
        #expect(received.count == 50)
    }

    @Test func messagesThatAreNotValidAreIgnoredAndTheConnectionGoesOn() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let client = try #require(YouTubeTestClient(path: path))
        client.sendFrame(Data("not json".utf8))
        client.sendFrame(Data())
        client.sendFrame(Data(#"{"v":2,"type":"clear","videoId":"abcdefghijk"}"#.utf8))
        client.sendFrame(Data(#"{"v":1,"type":"seek","videoId":"abcdefghijk"}"#.utf8))
        client.sendFrame(Data(#"{"v":1,"type":"clear","videoId":"short"}"#.utf8))
        client.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.clear()))
        await waitUntil { !received.isEmpty }
        #expect(received == [YouTubeTestMessages.clear()])
    }

    @Test func aLengthAboveFourMebibytesClosesThatConnectionButNotTheServer() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let bad = try #require(YouTubeTestClient(path: path))
        bad.send(Data([0x00, 0x40, 0x00, 0x01]) + Data("x".utf8))
        await waitUntil { bad.isClosedByServer }
        #expect(bad.isClosedByServer)
        let good = try #require(YouTubeTestClient(path: path))
        good.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.clear()))
        await waitUntil { !received.isEmpty }
        #expect(received == [YouTubeTestMessages.clear()])
    }

    @Test func severalClientsAtOnceAreAllServed() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let first = try #require(YouTubeTestClient(path: path))
        let second = try #require(YouTubeTestClient(path: path))
        first.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.clear("aaaaaaaaaaa")))
        second.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.clear("bbbbbbbbbbb")))
        await waitUntil { received.count == 2 }
        #expect(Set(received.map(\.videoID)) == ["aaaaaaaaaaa", "bbbbbbbbbbb"])
    }

    @Test func aClientThatClosesIsForgottenAndAnotherMayConnectLater() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        do {
            let client = try #require(YouTubeTestClient(path: path))
            client.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.clear("aaaaaaaaaaa")))
            await waitUntil { received.count == 1 }
        }
        let again = try #require(YouTubeTestClient(path: path))
        again.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.clear("bbbbbbbbbbb")))
        await waitUntil { received.count == 2 }
        #expect(received.map(\.videoID) == ["aaaaaaaaaaa", "bbbbbbbbbbb"])
    }

    @Test func connectionsBeyondTheLimitAreClosed() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let clients = try (0..<YouTubeBridgeServer.maxConnections + 2).map { _ in try #require(YouTubeTestClient(path: path)) }
        await waitUntil { clients.filter(\.isClosedByServer).count == 2 }
        #expect(clients.filter(\.isClosedByServer).count == 2, "\(clients.map(\.isClosedByServer))")
        #expect(!clients[0].isClosedByServer)
    }

    // MARK: through the host

    @Test func theHostCLIAndTheServerUnderstandEachOther() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        var fds: [Int32] = [0, 0]
        #expect(pipe(&fds) == 0)
        let readEnd = fds[0]
        let writeEnd = fds[1]
        let socketPath = path
        let finished = Finished()
        Thread.detachNewThread {
            _ = YouTubeHostCLI.run(stdin: FileDescriptorReader(fileDescriptor: readEnd), socketPath: socketPath, reconnectInterval: 0.05)
            close(readEnd)
            finished.flag.withLock { $0 = true }
        }
        // The host forgets a video's captions when it is cleared, so it must be connected before the messages come.
        await waitUntil { server.connectionCount == 1 }
        let sent = [YouTubeTestMessages.captions(), YouTubeTestMessages.playback(), YouTubeTestMessages.clear()]
        for message in sent {
            let json = YouTubeTestMessages.json(message)
            let frame = withUnsafeBytes(of: UInt32(json.count)) { Data($0) } + json
            frame.withUnsafeBytes { _ = write(writeEnd, $0.baseAddress, $0.count) }
        }
        close(writeEnd)
        await waitUntil { received.count == 3 }
        #expect(received == sent)
        #expect(await waitUntil { finished.flag.withLock { $0 } })
    }

    // MARK: lifecycle

    @Test func stopClosesTheClientsAndRemovesTheSocket() async throws {
        let server = makeServer()
        try server.start()
        let client = try #require(YouTubeTestClient(path: path))
        #expect(FileManager.default.fileExists(atPath: path))
        server.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
        await waitUntil { client.isClosedByServer }
        #expect(client.isClosedByServer)
        #expect(YouTubeTestClient(path: path) == nil)
    }

    @Test func aStaleSocketFileIsReplaced() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: URL(filePath: path))
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let client = try #require(YouTubeTestClient(path: path))
        client.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.clear()))
        await waitUntil { !received.isEmpty }
        #expect(received.count == 1)
    }

    @Test func startingAgainReplacesTheOldListener() async throws {
        let server = makeServer()
        try server.start()
        try server.start()
        defer { server.stop() }
        let client = try #require(YouTubeTestClient(path: path))
        client.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.clear()))
        await waitUntil { !received.isEmpty }
        #expect(received.count == 1)
    }

    @Test func anExistingDirectoryIsMadePrivateToo() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        #expect(try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int == 0o700)
    }

    @Test func callbacksQueuedBeforeStopAreDropped() async throws {
        let server = makeServer()
        try server.start()
        let client = try #require(YouTubeTestClient(path: path))
        client.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.clear()))
        // Blocks the main thread, so the frame is read and handed to the main queue but not yet delivered.
        usleep(300_000)
        server.stop()
        try await Task.sleep(for: .milliseconds(200))
        #expect(received.isEmpty)
    }

    @Test func aServerThatIsDroppedWithoutStopRemovesItsSocket() throws {
        do {
            let server = makeServer()
            try server.start()
            #expect(FileManager.default.fileExists(atPath: path))
        }
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    // MARK: refusing to start

    /// A folder of another user, as when someone made `/tmp/mynotch-<uid>` before the app did. `/Library` is the
    /// system's; the check comes before anything is changed or created there.
    @Test(.enabled(if: geteuid() != 0)) func aDirectoryOfAnotherUserIsRefused() {
        let server = YouTubeBridgeServer(socketPath: "/Library/youtube.sock") { _ in }
        #expect(throws: YouTubeBridgeServer.StartError.directoryNotOwned) { try server.start() }
    }

    @Test func aPathThatDoesNotFitIsATypedError() {
        let long = "/tmp/" + String(repeating: "d", count: 120) + "/youtube.sock"
        let server = YouTubeBridgeServer(socketPath: long) { _ in }
        #expect(throws: YouTubeBridgeServer.StartError.pathTooLong) { try server.start() }
        #expect(!FileManager.default.fileExists(atPath: long))
    }
}
