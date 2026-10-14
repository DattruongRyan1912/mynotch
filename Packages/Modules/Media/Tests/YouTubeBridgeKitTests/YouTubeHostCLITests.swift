import Foundation
import Testing
@testable import YouTubeBridgeKit

@Suite struct YouTubeHostCLITests {
    let server = FrameServer()
    let clock = TestClock()

    static func captions(_ videoID: String, text: String = "alpha") -> [String: Any] {
        YouTubeMessageTests.captions(videoID: videoID, events: [["t": 1.0, "d": 2.0, "text": text]])
    }

    static func playback(_ videoID: String = YouTubeMessageTests.videoID, playing: Bool = true) -> [String: Any] {
        YouTubeMessageTests.playback(videoID: videoID, playing: playing)
    }

    static func clear(_ videoID: String) -> [String: Any] {
        ["v": 1, "type": "clear", "videoId": videoID]
    }

    /// How late the host gets to what is written to its stdin: none, and a thread that is slow to run. The tests that
    /// change what the host sees (start or stop the app, move the clock) after sending something run with both, since
    /// a message in the pipe is not yet a message the host has dealt with.
    static let readDelays: [TimeInterval] = [0, 0.15]

    func start(on path: String? = nil, expectedOwner: uid_t = geteuid(), readDelay: TimeInterval = 0) -> HostRun {
        HostRun(socketPath: path ?? server.path, clock: clock, expectedOwner: expectedOwner, readDelay: readDelay)
    }

    // MARK: forwarding

    @Test func everyValidMessageIsForwardedAsTheSameBytesInOrder() async throws {
        defer { server.remove() }
        try server.start()
        let host = start()
        await waitUntil { server.connectionCount == 1 }
        let sent = [
            host.sendJSON(Self.playback()), host.sendJSON(Self.captions("aaaaaaaaaaa")), host.sendJSON(Self.clear("aaaaaaaaaaa")),
        ]
        await waitUntil { server.frames.count == 3 }
        #expect(server.frames == sent)
        #expect(await host.finish() == 0)
    }

    @Test func invalidMessagesAreDroppedAndTheStreamGoesOn() async throws {
        defer { server.remove() }
        try server.start()
        let host = start()
        await waitUntil { server.connectionCount == 1 }
        host.send(Data("not json".utf8))
        host.send(Data())
        host.sendJSON(["v": 2, "type": "clear", "videoId": "aaaaaaaaaaa"])
        host.sendJSON(Self.clear("short"))
        let valid = host.sendJSON(Self.clear("bbbbbbbbbbb"))
        await waitUntil { !server.frames.isEmpty }
        #expect(server.frames == [valid])
        #expect(await host.finish() == 0)
    }

    @Test func aMessageTooBigForTheAppSocketIsDroppedButStillReadToTheEnd() async throws {
        defer { server.remove() }
        try server.start()
        let host = start()
        await waitUntil { server.connectionCount == 1 }
        // Valid JSON, padded with spaces past the frame limit.
        let padded = Data(#"{"v":1,"type":"clear","videoId":"aaaaaaaaaaa"}"#.utf8) + Data(repeating: 0x20, count: AppFrame.maxLength)
        host.send(padded)
        let next = host.sendJSON(Self.clear("bbbbbbbbbbb"))
        await waitUntil { !server.frames.isEmpty }
        #expect(server.frames == [next])
        #expect(await host.finish() == 0)
    }

    @Test func aLengthChromeNeverSendsEndsTheRunWithoutTheInputBeingClosed() async {
        defer { server.remove() }
        let host = start()
        host.writeRaw(withUnsafeBytes(of: UInt32(NativeMessageReader<ScriptedReader>.maxLength + 1)) { Data($0) })
        #expect(await waitUntil { host.exitCode == 0 })
        #expect(await host.finish() == 0)
    }

    @Test func theRunEndsWithZeroWhenTheInputEndsEvenIfTheAppWasNeverThere() async {
        defer { server.remove() }
        let host = start()
        #expect(await host.finish() == 0)
        #expect(server.connectionCount == 0)
    }

    // MARK: connecting

    @Test func theHostReconnectsOnItsOwnEveryTwoSecondsByDefault() {
        #expect(YouTubeHostCLI.reconnectInterval == 2)
    }

    @Test(arguments: readDelays) func theAppMayStartAfterTheHostAndMessagesInBetweenAreDropped(readDelay: TimeInterval) async throws {
        defer { server.remove() }
        let host = start(readDelay: readDelay)
        // Nothing is listening: a clear is not kept for later, unlike captions and playback.
        host.sendJSON(Self.clear("aaaaaaaaaaa"))
        // The host has dealt with it, so it was dropped, before the app appears.
        await host.waitUntilHandled()
        try server.start()
        await waitUntil { server.connectionCount == 1 }
        #expect(server.connectionCount == 1)
        let after = host.sendJSON(Self.clear("bbbbbbbbbbb"))
        await waitUntil { !server.frames.isEmpty }
        #expect(server.frames == [after])
        #expect(await host.finish() == 0)
    }

    @Test(arguments: readDelays) func anAppThatQuitsAndComesBackIsReconnectedTo(readDelay: TimeInterval) async throws {
        defer { server.remove() }
        try server.start()
        let host = start(readDelay: readDelay)
        await waitUntil { server.connectionCount == 1 }
        server.stop()
        // The host notices on its own, while nothing is being sent, and a message sent meanwhile is lost.
        await host.waitForLog(containing: "app socket disconnected: peer closed")
        host.sendJSON(Self.clear("aaaaaaaaaaa"))
        // Dealt with while the app is away: the pipe alone does not say the host has read it.
        await host.waitUntilHandled()
        try server.start()
        await waitUntil { server.connectionCount == 2 }
        #expect(server.connectionCount == 2)
        let after = host.sendJSON(Self.clear("bbbbbbbbbbb"))
        await waitUntil { server.frames.contains(after) }
        #expect(server.frames == [after])
        #expect(await host.finish() == 0)
    }

    @Test(arguments: readDelays) func aSocketOfAnotherUserGetsNothingNotEvenTheReplay(readDelay: TimeInterval) async throws {
        defer { server.remove() }
        try server.start()
        let host = start(expectedOwner: geteuid() &+ 1, readDelay: readDelay)
        // Captions are what a connection would replay at once, and a clear what a live one would carry.
        host.sendJSON(Self.captions("aaaaaaaaaaa"))
        host.sendJSON(Self.clear("bbbbbbbbbbb"))
        // The host may connect to find out whose socket it is, but it hangs up before it sends anything.
        await waitUntil { server.connectionCount >= 2 }
        #expect(server.connectionCount >= 2)
        // It has looked at whose socket this is, found it is not the user's, and dealt with both messages.
        await host.waitForLog(containing: "app socket unavailable reason=other-user")
        await host.waitUntilHandled()
        #expect(server.frames.isEmpty)
        #expect(await host.finish() == 0)
    }

    // MARK: an app that closes the socket

    @Test func aSendToAPeerThatHasClosedFailsInsteadOfRaisingSIGPIPE() async throws {
        let watch = SigpipeWatch()
        let closing = FrameServer(closesClientsAtOnce: true)
        defer { closing.remove() }
        try closing.start()
        // The host connects once, at the start, and does not look at the socket again for a minute.
        let host = HostRun(socketPath: closing.path, reconnectInterval: 60, clock: clock)
        await waitUntil { closing.hangUpCount == 1 }
        #expect(closing.hangUpCount == 1)
        // These go to a socket whose other end is closed.
        host.sendJSON(Self.clear("aaaaaaaaaaa"))
        host.sendJSON(Self.playback())
        host.sendJSON(Self.captions("bbbbbbbbbbb"))
        #expect(await host.finish() == 0)
        #expect(watch.count == 0, "a send to a closed socket must not raise SIGPIPE (SO_NOSIGPIPE)")
    }

    @Test func theHostKeepsRunningAndReplaysToTheNextAppAfterOneThatHungUp() async throws {
        let watch = SigpipeWatch()
        let closing = FrameServer(closesClientsAtOnce: true)
        defer { closing.remove() }
        try closing.start()
        let host = start(on: closing.path)
        let captions = host.sendJSON(Self.captions("aaaaaaaaaaa"))
        // Each reconnection replays the captions to a peer that has just gone, and live messages hit the dead ones too.
        await waitUntil { closing.hangUpCount >= 3 }
        for _ in 0..<20 {
            host.sendJSON(Self.clear("bbbbbbbbbbb"))
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(closing.hangUpCount >= 3)
        // All of those were dealt with against dead peers; none may be left to go to the next app.
        await host.waitUntilHandled()

        closing.stop()
        let real = FrameServer(directory: closing.directory)
        defer { real.stop() }
        try real.start()
        await waitUntil { real.frames.count == 1 }
        #expect(real.frames == [captions])
        #expect(watch.count == 0, "a send to a closed socket must not raise SIGPIPE (SO_NOSIGPIPE)")
        #expect(await host.finish() == 0)
    }

    // MARK: replay

    @Test(arguments: readDelays) func theLatestCaptionsOfEachVideoAndThenThePlaybackAreReplayedOnConnecting(readDelay: TimeInterval) async throws {
        defer { server.remove() }
        let host = start(readDelay: readDelay)
        let first = host.sendJSON(Self.captions("aaaaaaaaaaa"))
        let second = host.sendJSON(Self.captions("bbbbbbbbbbb"))
        let playing = host.sendJSON(Self.playback("bbbbbbbbbbb"))
        await host.waitUntilHandled()
        try server.start()
        await waitUntil { server.frames.count == 3 }
        #expect(server.frames == [first, second, playing])
        // New messages follow the replay.
        let after = host.sendJSON(Self.clear("ccccccccccc"))
        await waitUntil { server.frames.count == 4 }
        #expect(server.frames.last == after)
        #expect(await host.finish() == 0)
    }

    @Test(arguments: readDelays) func aVideoHasOnlyItsLatestCaptionsAndOnlyTheLatestPlaybackIsKept(readDelay: TimeInterval) async throws {
        defer { server.remove() }
        let host = start(readDelay: readDelay)
        host.sendJSON(Self.captions("aaaaaaaaaaa", text: "old"))
        host.sendJSON(Self.playback(playing: false))
        let newer = host.sendJSON(Self.captions("aaaaaaaaaaa", text: "new"))
        let latest = host.sendJSON(Self.playback(playing: true))
        await host.waitUntilHandled()
        try server.start()
        // The line says how much was replayed, and it is written once all of it has been sent.
        await host.waitForLog(containing: "app socket connected replayed-captions=1 replayed-playback=true")
        await waitUntil { server.frames.count == 2 }
        #expect(server.frames == [newer, latest])
        #expect(await host.finish() == 0)
    }

    @Test(arguments: readDelays) func clearDropsThatVideosCaptionsFromTheReplay(readDelay: TimeInterval) async throws {
        defer { server.remove() }
        let host = start(readDelay: readDelay)
        host.sendJSON(Self.captions("aaaaaaaaaaa"))
        let kept = host.sendJSON(Self.captions("bbbbbbbbbbb"))
        host.sendJSON(Self.clear("aaaaaaaaaaa"))
        await host.waitUntilHandled()
        try server.start()
        await host.waitForLog(containing: "app socket connected replayed-captions=1 replayed-playback=false")
        await waitUntil { !server.frames.isEmpty }
        #expect(server.frames == [kept])
        #expect(await host.finish() == 0)
    }

    @Test(arguments: readDelays) func atMostThreeVideosAreKeptTheOldestGoingFirst(readDelay: TimeInterval) async throws {
        defer { server.remove() }
        let host = start(readDelay: readDelay)
        host.sendJSON(Self.captions("aaaaaaaaaaa"))
        let second = host.sendJSON(Self.captions("bbbbbbbbbbb"))
        let third = host.sendJSON(Self.captions("ccccccccccc"))
        let fourth = host.sendJSON(Self.captions("ddddddddddd"))
        await host.waitUntilHandled()
        try server.start()
        await host.waitForLog(containing: "app socket connected replayed-captions=3 replayed-playback=false")
        await waitUntil { server.frames.count == 3 }
        #expect(server.frames == [second, third, fourth])
        #expect(await host.finish() == 0)
    }

    @Test(arguments: readDelays) func aPlaybackOlderThanTenSecondsIsNotReplayedButCaptionsAre(readDelay: TimeInterval) async throws {
        defer { server.remove() }
        let host = start(readDelay: readDelay)
        let captions = host.sendJSON(Self.captions("aaaaaaaaaaa"))
        host.sendJSON(Self.playback("aaaaaaaaaaa"))
        // The playback has to be stamped before the clock moves on.
        await host.waitUntilHandled()
        clock.advance(by: 10.5)
        try server.start()
        await host.waitForLog(containing: "app socket connected replayed-captions=1 replayed-playback=false")
        await waitUntil { !server.frames.isEmpty }
        #expect(server.frames == [captions])
        #expect(await host.finish() == 0)
    }

    @Test(arguments: readDelays) func restartingOnlyTheAppReplaysAgain(readDelay: TimeInterval) async throws {
        defer { server.remove() }
        try server.start()
        let host = start(readDelay: readDelay)
        await waitUntil { server.connectionCount == 1 }
        let captions = host.sendJSON(Self.captions("aaaaaaaaaaa"))
        let playing = host.sendJSON(Self.playback("aaaaaaaaaaa"))
        await waitUntil { server.frames.count == 2 }
        #expect(server.frames == [captions, playing])
        server.stop()
        await host.waitForLog(containing: "app socket disconnected")

        // A fresh app instance on the same path.
        let restarted = FrameServer(directory: server.directory)
        try restarted.start()
        await waitUntil { restarted.frames.count == 2 }
        #expect(restarted.frames == [captions, playing])
        restarted.stop()
        #expect(await host.finish() == 0)
    }

    @Test(arguments: readDelays) func aClearAndAStalePausedPlaybackLeaveNothingToReplay(readDelay: TimeInterval) async throws {
        defer { server.remove() }
        let host = start(readDelay: readDelay)
        host.sendJSON(Self.clear("aaaaaaaaaaa"))
        host.sendJSON(Self.playback(playing: false))
        // The playback has to be stamped before the clock moves on.
        await host.waitUntilHandled()
        clock.advance(by: 60)
        try server.start()
        await waitUntil { server.connectionCount == 1 }
        await host.waitForLog(containing: "app socket connected replayed-captions=0 replayed-playback=false")
        #expect(server.frames.isEmpty)
        #expect(await host.finish() == 0)
    }
}
