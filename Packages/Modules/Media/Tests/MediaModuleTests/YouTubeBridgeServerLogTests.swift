import Foundation
import Testing
@testable import MediaModule
@testable import YouTubeBridgeKit

/// What the receiver writes to the log (through an injected sink), and that it holds nothing private.
@Suite final class YouTubeBridgeServerLogTests {
    let directory = URL(filePath: "/tmp/mn-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)
    var path: String { directory.appending(path: "youtube.sock").path }
    let recorder = LogRecorder()
    let clock = TestClock()
    var received: [YouTubeMessage] = []

    deinit { try? FileManager.default.removeItem(at: directory) }

    func makeServer() -> YouTubeBridgeServer {
        YouTubeBridgeServer(socketPath: path, log: recorder.log, now: { [clock] in clock.now }) { [unowned self] in received.append($0) }
    }

    func frame(_ message: YouTubeMessage) -> Data {
        AppFrame.encode(YouTubeTestMessages.json(message))!
    }

    // MARK: connections

    @Test func listeningAndStoppingAreLogged() throws {
        let server = makeServer()
        try server.start()
        #expect(recorder.lines == ["app listening"])
        server.stop()
        #expect(recorder.lines == ["app listening", "app stopped"])
        server.stop()
        #expect(recorder.lines.count == 2, "stopping twice says it once")
    }

    @Test func aConnectionIsLoggedWhenItIsAcceptedAndWhenItEnds() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        do {
            let client = try #require(YouTubeTestClient(path: path))
            await waitUntil { !recorder.lines(containing: "accepted").isEmpty }
            #expect(recorder.lines.contains("app connection accepted open=1"))
            _ = client
        }
        await waitUntil { !recorder.lines(containing: "connection closed").isEmpty }
        #expect(recorder.lines.contains("app connection closed: peer closed"))
    }

    @Test func aConnectionOverTheLimitIsRefusedWithItsReason() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let clients = try (0..<YouTubeBridgeServer.maxConnections + 1).map { _ in try #require(YouTubeTestClient(path: path)) }
        await waitUntil { !recorder.lines(containing: "refused").isEmpty }
        #expect(recorder.lines.filter { $0 == "app connection refused: limit" }.count == 1)
        #expect(recorder.lines(containing: "accepted").count == YouTubeBridgeServer.maxConnections)
        _ = clients
    }

    @Test func aLengthAboveTheLimitIsLoggedAsTheReasonTheConnectionWasClosed() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let client = try #require(YouTubeTestClient(path: path))
        client.send(Data([0x00, 0x40, 0x00, 0x01]) + Data("x".utf8))
        await waitUntil { !recorder.lines(containing: "connection closed").isEmpty }
        #expect(recorder.lines.contains("app connection closed: frame too large"))
    }

    // MARK: counts

    @Test func framesReceivedAreCountedPerTypeInASummaryEveryTenSeconds() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let client = try #require(YouTubeTestClient(path: path))
        for message in [YouTubeTestMessages.playback(), YouTubeTestMessages.playback(), YouTubeTestMessages.captions(), YouTubeTestMessages.diag()] {
            client.send(frame(message))
        }
        await waitUntil { received.count == 4 }
        #expect(recorder.lines(containing: "app frames").isEmpty, "not before ten seconds")

        clock.advance(by: 10)
        client.send(frame(YouTubeTestMessages.clear()))
        await waitUntil { !recorder.lines(containing: "app frames").isEmpty }
        #expect(recorder.lines(containing: "app frames") == ["app frames received[captions=1 clear=1 diag=1 playback=2]"])
    }

    @Test func theLastCountsAreSaidWhenTheConnectionEndsAndWhenTheServerStops() async throws {
        let server = makeServer()
        try server.start()
        do {
            let client = try #require(YouTubeTestClient(path: path))
            client.send(frame(YouTubeTestMessages.playback()))
            await waitUntil { received.count == 1 }
        }
        await waitUntil { !recorder.lines(containing: "app frames").isEmpty }
        #expect(recorder.lines(containing: "app frames") == ["app frames received[playback=1]"])

        let again = try #require(YouTubeTestClient(path: path))
        again.send(frame(YouTubeTestMessages.clear()))
        await waitUntil { received.count == 2 }
        server.stop()
        #expect(recorder.lines.last == "app stopped")
        #expect(recorder.lines.dropLast().last == "app frames received[clear=1]")
    }

    // MARK: rejects

    @Test func aRejectedFrameIsAnnouncedOnceWithItsReasonAndCountedForTheSummary() async throws {
        let server = makeServer()
        try server.start()
        defer { server.stop() }
        let client = try #require(YouTubeTestClient(path: path))
        for _ in 0..<3 { client.sendFrame(Data("not json".utf8)) }
        client.sendFrame(Data(#"{"v":1,"type":"clear","videoId":"short"}"#.utf8))
        client.sendFrame(Data(#"{"v":2,"type":"clear","videoId":"abcdefghijk"}"#.utf8))
        client.sendFrame(Data(#"{"v":1,"type":"seek"}"#.utf8))
        client.sendFrame(Data(#"{"v":1,"type":"diag","where":"sw","event":"nonsense"}"#.utf8))
        client.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.clear()))
        await waitUntil { received.count == 1 }
        // One announcement per reason, however often it happens.
        #expect(recorder.lines.filter { $0.hasPrefix("app rejected frame: ") } == [
            "app rejected frame: malformed", "app rejected frame: invalid-clear", "app rejected frame: unsupported-version",
            "app rejected frame: unknown-type", "app rejected frame: invalid-diag",
        ])

        clock.advance(by: 10)
        client.sendFrame(YouTubeTestMessages.json(YouTubeTestMessages.clear()))
        await waitUntil { !recorder.lines(containing: "app frames").isEmpty }
        #expect(recorder.lines(containing: "app frames") == [
            "app frames received[clear=2] rejected[invalid-clear=1 invalid-diag=1 malformed=3 unknown-type=1 unsupported-version=1]",
        ])
    }

    // MARK: nothing private

    @Test func noLineHoldsATitleAVideoIdCaptionTextOrAUrl() async throws {
        let server = makeServer()
        try server.start()
        let secretID = "abcdefghijk"
        let secretTitle = "Zebra Quartz Secret Title"
        let secretWords = "hidden caption words"
        let client = try #require(YouTubeTestClient(path: path))
        client.send(frame(YouTubeTestMessages.captions(secretID, [CaptionEvent(time: 1, duration: 2, text: secretWords)])))
        client.send(frame(YouTubeTestMessages.playback(secretID, title: secretTitle)))
        client.send(frame(YouTubeTestMessages.diag("page-timedtext json3 events=1", from: .page)))
        client.sendFrame(Data(#"{"v":1,"type":"diag","where":"content","event":"content-tick-error https://www.youtube.com/watch?v=abcdefghijk"}"#.utf8))
        client.sendFrame(Data("title=\(secretTitle) \(secretID)".utf8))
        client.sendFrame(Data(#"{"v":1,"type":"playback","videoId":"abcdefghijk","title":"Zebra Quartz Secret Title","time":-1,"playing":true,"rate":1}"#.utf8))
        await waitUntil { received.count == 3 }
        clock.advance(by: 10)
        client.send(frame(YouTubeTestMessages.clear(secretID)))
        await waitUntil { received.count == 4 }
        server.stop()
        #expect(recorder.lines.count >= 6, "\(recorder.lines)")
        recorder.expectNothingPrivate([secretID, secretTitle, "Zebra", "Quartz", secretWords, "hidden", "youtube", "/tmp", directory.path])
    }

    // MARK: failing to start

    @Test func theReasonsForNotListeningAreFixedWords() {
        #expect(YouTubeBridgeServer.StartError.pathTooLong.reason == "path-too-long")
        #expect(YouTubeBridgeServer.StartError.directoryNotOwned.reason == "folder-not-owned")
        #expect(YouTubeBridgeServer.StartError.socket(errno: 48).reason == "socket-error-48")
    }
}
