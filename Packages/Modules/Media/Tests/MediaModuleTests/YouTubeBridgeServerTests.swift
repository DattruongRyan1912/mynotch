import Foundation
import MyNotchTestSupport
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

    /// The server closed this connection (what it has sent and not been read does not count: a command is not a close).
    var isClosedByServer: Bool {
        var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&poller, 1, 0) > 0 else { return false }
        if poller.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 { return true }
        var byte: UInt8 = 0
        let count = recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
        return count == 0 || (count < 0 && errno != EAGAIN && errno != EINTR)
    }

    /// The frames the server sends, waiting up to `seconds` for each; fewer than `count` when they do not come. The limit
    /// only matters when something is wrong, so it is very generous: a busy machine can hold a thread back for seconds.
    func receiveFrames(count: Int, seconds: Double = 60) -> [Data] {
        var decoder = AppFrameDecoder()
        var frames: [Data] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        while frames.count < count {
            if case .frame(let frame) = decoder.next() {
                frames.append(frame)
                continue
            }
            var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, Int32(seconds * 1000)) > 0 else { break }
            let received = recv(fd, &buffer, buffer.count, 0)
            guard received > 0 else { break }
            decoder.append(Data(buffer[0..<received]))
        }
        return frames
    }

    /// Whether the server has sent anything that has not been read yet. A write is in this socket's buffer once `send`
    /// has returned, so a test that asks after the server's call has nothing to wait for.
    var hasUnreadData: Bool {
        var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        return poll(&poller, 1, 0) > 0 && poller.revents & Int16(POLLIN) != 0
    }
}

/// SIGPIPEs raised in this process so far, counted by `SigpipeCounter`.
private let sigpipesRaised = Atomic<Int>(0)

/// Counts SIGPIPE instead of letting it end the process, which is its default action: a send to a closed socket that is not
/// guarded against it would otherwise take the whole test run down instead of failing one test. Only one test uses it.
private final class SigpipeCounter: Sendable {
    private let previous: Mutex<sigaction>
    private let baseline = sigpipesRaised.load(ordering: .relaxed)

    init() {
        var action = sigaction()
        action.__sigaction_u.__sa_handler = { _ in sigpipesRaised.add(1, ordering: .relaxed) }
        sigemptyset(&action.sa_mask)
        var old = sigaction()
        sigaction(SIGPIPE, &action, &old)
        previous = Mutex(old)
    }

    deinit {
        previous.withLock { _ = sigaction(SIGPIPE, &$0, nil) }
    }

    var seen: Int { sigpipesRaised.load(ordering: .relaxed) - baseline }
}

/// Waits on the main actor, where the callbacks run, until `condition` holds. The limit only matters when something is
/// wrong, so it is very generous: a busy machine can hold a thread back for many seconds.
@discardableResult
func waitUntil(seconds: Double = 60, _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while !condition() {
        if ContinuousClock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

/// Like `waitUntil`, but on this thread, so the main queue does not run meanwhile: for a test that needs what other
/// threads hand to the main queue to be queued and not yet delivered.
func waitWithoutLettingTheMainQueueRun(seconds: Double = 60, _ condition: () -> Bool) -> Bool {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while !condition() {
        if ContinuousClock.now > deadline { return false }
        usleep(1_000)
    }
    return true
}

/// Set by a thread that ends, for a test to wait on.
final class Finished: Sendable {
    let flag = Mutex(false)
}

@Suite final class YouTubeBridgeServerTests {
    /// Unix socket paths are limited to 104 bytes, so the folder is short and outside the sandboxed temp dir.
    let directory = ScratchFolders.shared.reserveShort()
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

    // MARK: commands to the host

    /// A playback from `client`, which is how the server learns which host the page is behind; waits until it has been delivered.
    func sendPlayback(from client: YouTubeTestClient, time: Double = 1) async {
        let before = received.count
        client.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.playback(time: time)))
        await waitUntil { received.count == before + 1 }
    }

    @Test func aCommandGoesAsAFrameToTheHostWhosePlaybackCameLast() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let first = try #require(YouTubeTestClient(path: path))
        let second = try #require(YouTubeTestClient(path: path))
        await sendPlayback(from: first)
        await sendPlayback(from: second)
        #expect(server.send(.next))
        #expect(second.receiveFrames(count: 1) == [YouTubeCommand.next.json])
        #expect(!first.hasUnreadData, "only the host that is behind the playing page is asked")

        await sendPlayback(from: first, time: 2)
        #expect(server.send(.previous))
        #expect(first.receiveFrames(count: 1) == [YouTubeCommand.previous.json])
        #expect(!second.hasUnreadData)
    }

    @Test func theFrameIsExactlyTheCommandsFrame() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let client = try #require(YouTubeTestClient(path: path))
        await sendPlayback(from: client)
        #expect(server.send(.previous))
        var raw = [UInt8](repeating: 0, count: 64)
        var poller = pollfd(fd: client.fd, events: Int16(POLLIN), revents: 0)
        #expect(poll(&poller, 1, 60_000) > 0)
        let count = recv(client.fd, &raw, raw.count, 0)
        #expect(Data(raw[0..<max(count, 0)]) == YouTubeCommand.previous.frame)
    }

    @Test func withoutAPlaybackThereIsNoHostToSendToAndNothingIsSent() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        #expect(!server.send(.next), "no connection at all")
        let client = try #require(YouTubeTestClient(path: path))
        client.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.clear()))
        client.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.captions()))
        client.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.diag("content-start", from: .content)))
        await waitUntil { received.count == 3 }
        #expect(!server.send(.next), "only a playback says where the page is")
        #expect(!client.hasUnreadData)
    }

    @Test func aHostThatClosedIsNotWrittenTo() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        do {
            let client = try #require(YouTubeTestClient(path: path))
            await sendPlayback(from: client)
        }
        await waitUntil { server.connectionCount == 0 }
        #expect(!server.send(.next))
    }

    @Test func aStoppedServerSendsNothing() async throws {
        let server = makeServer()
        try server.start()
        let client = try #require(YouTubeTestClient(path: path))
        await sendPlayback(from: client)
        server.stop()
        #expect(!server.send(.next))
        #expect(YouTubeTestClient(path: path) == nil)
    }

    @Test func sendingToAHostThatHasJustGoneNeitherRaisesSIGPIPENorLeavesItListed() async throws {
        let counter = SigpipeCounter()
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let client = try #require(YouTubeTestClient(path: path))
        await sendPlayback(from: client)
        shutdown(client.fd, SHUT_RDWR)
        // Whether the server has noticed yet or not, none of these may end the process.
        for _ in 0..<20 {
            _ = server.send(.next)
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(counter.seen == 0, "a send to a closed socket must not raise SIGPIPE (SO_NOSIGPIPE)")
        await waitUntil { server.connectionCount == 0 }
        #expect(server.connectionCount == 0)
        #expect(!server.send(.next))
    }

    @Test func everyConnectionIsGuardedAgainstSIGPIPEBecauseTheAppWritesToThem() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let clients = try (0..<3).map { _ in try #require(YouTubeTestClient(path: path)) }
        await waitUntil { server.connectionCount == 3 }
        #expect(server.connectionCount == 3)
        #expect(server.connectionsAreGuardedAgainstSIGPIPE)
        withExtendedLifetime(clients) {}
    }

    @Test func theServerNeverSendsAnythingUnasked() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let client = try #require(YouTubeTestClient(path: path))
        for message in [YouTubeTestMessages.captions(), YouTubeTestMessages.playback(), YouTubeTestMessages.clear()] {
            client.sendFrame(YouTubeTestMessages.json(message))
        }
        await waitUntil { received.count == 3 }
        #expect(!client.hasUnreadData)
    }

    @Test func aCommandReachesTheHostsStdoutAsANativeMessage() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        var stdin: [Int32] = [0, 0]
        var stdout: [Int32] = [0, 0]
        #expect(pipe(&stdin) == 0)
        #expect(pipe(&stdout) == 0)
        let socketPath = path
        let finished = Finished()
        let output = FileDescriptorWriter(fileDescriptor: stdout[1])
        let input = stdin[0]
        Thread.detachNewThread {
            _ = YouTubeHostCLI.run(
                stdin: FileDescriptorReader(fileDescriptor: input), socketPath: socketPath, reconnectInterval: 0.05,
                log: .silent, commandOutput: output
            )
            close(input)
            finished.flag.withLock { $0 = true }
        }
        await waitUntil { server.connectionCount == 1 }
        // The page's playback tells the server which connection to use, and the command comes back the same way.
        let json = YouTubeTestMessages.json(YouTubeTestMessages.playback())
        let frame = withUnsafeBytes(of: UInt32(json.count)) { Data($0) } + json
        frame.withUnsafeBytes { _ = write(stdin[1], $0.baseAddress, $0.count) }
        await waitUntil { received.count == 1 }
        #expect(server.send(.next))
        var poller = pollfd(fd: stdout[0], events: Int16(POLLIN), revents: 0)
        #expect(poll(&poller, 1, 60_000) > 0, "the command did not come out of the host")
        var reader = NativeMessageReader(source: FileDescriptorReader(fileDescriptor: stdout[0]))
        #expect(reader.next() == .message(YouTubeCommand.next.json))
        close(stdin[1])
        #expect(await waitUntil { finished.flag.withLock { $0 } })
        close(stdout[0])
        close(stdout[1])
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
        let recorder = LogRecorder()
        let clock = TestClock()
        let server = YouTubeBridgeServer(socketPath: path, log: recorder.log, now: { [clock] in clock.now }) { [unowned self] in
            received.append($0)
        }
        try server.start()
        let client = try #require(YouTubeTestClient(path: path))
        // With ten seconds gone, the summary of the frames comes right after a frame has been handed to the main queue.
        clock.advance(by: 10)
        client.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.clear()))
        // Waits on this thread, so the frame is read and handed to the main queue but not yet delivered.
        #expect(waitWithoutLettingTheMainQueueRun { !recorder.lines(containing: "app frames").isEmpty })
        server.stop()
        await drainMainQueue()
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
