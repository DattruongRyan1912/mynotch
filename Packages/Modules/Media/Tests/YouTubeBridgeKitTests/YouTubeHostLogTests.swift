import Foundation
import Testing
@testable import YouTubeBridgeKit

/// What the host writes to the log (through an injected sink), and that it holds nothing private.
@Suite struct YouTubeHostLogTests {
    let server = FrameServer()
    let clock = TestClock()
    let recorder = LogRecorder()

    func start(
        launch: YouTubeHostLaunch = YouTubeHostLaunch(argumentCount: 2, parentName: "Google Chrome"), on path: String? = nil,
        readDelay: TimeInterval = 0
    ) -> HostRun {
        HostRun(socketPath: path ?? server.path, clock: clock, readDelay: readDelay, log: recorder.log, launch: launch)
    }

    static func diag(_ origin: String, _ event: String) -> [String: Any] {
        ["v": 1, "type": "diag", "where": origin, "event": event]
    }

    // MARK: lifecycle

    @Test func theHostSaysHowItWasStartedWithTheParentsNameOnly() async {
        defer { server.remove() }
        let host = start()
        #expect(await host.finish() == 0)
        #expect(recorder.lines.first == "host start argc=2 parent=Google Chrome")
    }

    @Test func theLaunchInfoHoldsTheNameOfTheParentNotItsPathOrArguments() {
        let launch = YouTubeHostLaunch.current
        #expect(launch.argumentCount == CommandLine.arguments.count)
        let name = launch.parentName ?? ""
        #expect(!name.isEmpty)
        #expect(!name.contains("/"))
        #expect(!name.contains("://"))
    }

    @Test func theEndOfTheInputIsLoggedAndSoIsALengthChromeNeverSends() async {
        defer { server.remove() }
        let closed = start()
        #expect(await closed.finish() == 0)
        #expect(recorder.lines.contains("host stdin closed"))

        let other = LogRecorder()
        let host = HostRun(socketPath: server.path, clock: clock, log: other.log)
        host.writeRaw(withUnsafeBytes(of: UInt32(NativeMessageReader<ScriptedReader>.maxLength + 1)) { Data($0) })
        #expect(await waitUntil { host.exitCode == 0 })
        #expect(other.lines.contains("host stdin out of step: length above the limit"))
        #expect(await host.finish() == 0)
    }

    @Test func theAppBeingAwayIsSaidOnceThenRemindedEveryThirtySecondsAndTheConnectionIsLogged() async throws {
        defer { server.remove() }
        let host = start()
        await waitUntil { !recorder.lines(containing: "app socket unavailable").isEmpty }
        // The round that said it was the first; three more (every 50 ms here) must not say it again.
        #expect(await host.waitForRounds(4))
        #expect(recorder.lines(containing: "app socket unavailable").count == 1)
        #expect(recorder.lines(containing: "app socket unavailable").first == "app socket unavailable reason=no-socket, trying again every 0s")
        #expect(recorder.lines(containing: "still unavailable").isEmpty, "not before thirty seconds")

        clock.advance(by: 30)
        await waitUntil { !recorder.lines(containing: "still unavailable").isEmpty }
        let reminders = recorder.lines(containing: "still unavailable")
        #expect(reminders.count == 1)
        #expect(reminders[0].hasPrefix("app socket still unavailable reason=no-socket attempts="))

        try server.start()
        await waitUntil { !recorder.lines(containing: "app socket connected").isEmpty }
        let connected = recorder.lines(containing: "app socket connected")
        #expect(connected.count == 1)
        #expect(connected[0].hasPrefix("app socket connected replayed-captions=0 replayed-playback=false after-failed-attempts="))

        server.stop()
        await waitUntil { !recorder.lines(containing: "app socket disconnected").isEmpty }
        #expect(recorder.lines.contains("app socket disconnected: peer closed"))
        #expect(await host.finish() == 0)
    }

    @Test(arguments: YouTubeHostCLITests.readDelays) func aConnectionWithAReplayNamesWhatItReplayed(readDelay: TimeInterval) async throws {
        defer { server.remove() }
        let host = start(readDelay: readDelay)
        host.sendJSON(YouTubeHostCLITests.captions("aaaaaaaaaaa"))
        host.sendJSON(YouTubeHostCLITests.captions("bbbbbbbbbbb"))
        host.sendJSON(YouTubeHostCLITests.playback())
        await host.waitUntilHandled()
        try server.start()
        await waitUntil { !recorder.lines(containing: "app socket connected").isEmpty }
        #expect(recorder.lines(containing: "app socket connected").first?.hasPrefix("app socket connected replayed-captions=2 replayed-playback=true") == true)
        #expect(await host.finish() == 0)
        #expect(recorder.lines.contains("app socket closed: host exit"))
    }

    // MARK: diagnostics

    @Test func aDiagIsLoggedAndForwardedToTheApp() async throws {
        defer { server.remove() }
        try server.start()
        let host = start()
        await waitUntil { server.connectionCount == 1 }
        let sent = host.sendJSON(Self.diag("sw", "sw-start v=0.1.1"))
        await waitUntil { !server.frames.isEmpty }
        #expect(server.frames == [sent])
        #expect(recorder.lines.contains("extension diag where=sw event=sw-start v=0.1.1"))
        #expect(await host.finish() == 0)
    }

    @Test func everyPartsEventsAreLogged() async throws {
        defer { server.remove() }
        try server.start()
        let host = start()
        await waitUntil { server.connectionCount == 1 }
        for (origin, event) in [("content", "content-cc on"), ("page", "page-timedtext json3 events=3"), ("sw", "sw-reconnect after=host-not-found failures=2")] {
            host.sendJSON(Self.diag(origin, event))
        }
        await waitUntil { server.frames.count == 3 }
        #expect(recorder.lines(containing: "extension diag").map { $0.dropFirst("extension diag ".count) } == [
            "where=content event=content-cc on", "where=page event=page-timedtext json3 events=3",
            "where=sw event=sw-reconnect after=host-not-found failures=2",
        ])
        #expect(await host.finish() == 0)
    }

    @Test(arguments: YouTubeHostCLITests.readDelays) func aDiagIsAboutNowSoItIsNeverReplayed(readDelay: TimeInterval) async throws {
        defer { server.remove() }
        let host = start(readDelay: readDelay)
        host.sendJSON(Self.diag("sw", "sw-start v=0.1.1"))
        // Dealt with while the app is away, whatever the pipe says.
        await host.waitUntilHandled()
        try server.start()
        // The line says nothing was replayed, and is written once the replay is over.
        await host.waitForLog(containing: "app socket connected replayed-captions=0 replayed-playback=false")
        #expect(server.frames.isEmpty)
        // It was still logged when it came, and counted as dropped for the app.
        #expect(recorder.lines.contains("extension diag where=sw event=sw-start v=0.1.1"))
        #expect(await host.finish() == 0)
        #expect(recorder.lines(containing: "dropped[app-away=1]").count == 1)
    }

    @Test func aDiagThatBreaksTheGrammarIsNeitherLoggedNorForwarded() async throws {
        defer { server.remove() }
        try server.start()
        let host = start()
        await waitUntil { server.connectionCount == 1 }
        for event in [
            "content-tick-error abcdefghijk", "content-tick-error https://example.com/watch?v=abcdefghijk",
            "page-timedtext json3 events=1 title=Secret", "sw-start v=1",
        ] {
            host.sendJSON(Self.diag(event.hasPrefix("sw") ? "content" : String(event.prefix { $0 != "-" }), event))
        }
        let valid = host.sendJSON(Self.diag("content", "content-cc off"))
        await waitUntil { !server.frames.isEmpty }
        #expect(server.frames == [valid])
        #expect(await host.finish() == 0)
        #expect(recorder.lines(containing: "extension diag") == ["extension diag where=content event=content-cc off"])
        #expect(recorder.lines(containing: "dropped[invalid-diag=4]").count == 1)
    }

    // MARK: counts

    @Test func framesForwardedAreCountedPerTypeInASummaryEveryTenSeconds() async throws {
        defer { server.remove() }
        try server.start()
        let host = start()
        await waitUntil { server.connectionCount == 1 }
        host.sendJSON(YouTubeHostCLITests.playback())
        host.sendJSON(YouTubeHostCLITests.playback())
        host.sendJSON(YouTubeHostCLITests.captions("aaaaaaaaaaa"))
        host.sendJSON(YouTubeHostCLITests.clear("aaaaaaaaaaa"))
        host.sendJSON(Self.diag("page", "page-seen fetch"))
        await waitUntil { server.frames.count == 5 }
        await host.waitUntilHandled()
        #expect(recorder.lines(containing: "host frames").isEmpty, "not before ten seconds")
        clock.advance(by: 10)
        await waitUntil { !recorder.lines(containing: "host frames").isEmpty }
        #expect(recorder.lines(containing: "host frames") == ["host frames forwarded[captions=1 clear=1 diag=1 playback=2]"])
        #expect(await host.finish() == 0)
    }

    @Test func framesDroppedAreCountedByReasonAndTheLastSummaryComesAtTheEnd() async throws {
        defer { server.remove() }
        let host = start()
        // The app is away for these.
        host.sendJSON(YouTubeHostCLITests.playback())
        host.send(Data("not json".utf8))
        host.send(Data(#"{"v":2,"type":"clear","videoId":"abcdefghijk"}"#.utf8))
        host.sendJSON(["v": 1, "type": "seek", "videoId": "abcdefghijk"])
        host.sendJSON(YouTubeMessageTests.playback(rate: 0))
        host.sendJSON(YouTubeMessageTests.captions(videoID: "short"))
        host.sendJSON(["v": 1, "type": "clear", "videoId": "short"])
        host.send(Data(#"{"v":1,"type":"clear","videoId":"abcdefghijk"}"#.utf8) + Data(repeating: 0x20, count: AppFrame.maxLength))
        #expect(await host.finish() == 0)
        #expect(recorder.lines.last == "host frames dropped[app-away=1 invalid-captions=1 invalid-clear=1 invalid-playback=1 malformed=1 too-large=1 unknown-type=1 unsupported-version=1]")
    }

    // MARK: nothing private

    @Test(arguments: YouTubeHostCLITests.readDelays) func noLineHoldsATitleAVideoIdCaptionTextAUrlOrAPath(readDelay: TimeInterval) async throws {
        defer { server.remove() }
        let host = start(readDelay: readDelay)
        let secretID = "abcdefghijk"
        let secretTitle = "Zebra Quartz Secret Title"
        let secretWords = "hidden caption words"
        // Everything that can happen: away, connecting, replaying, forwarding, dropping, diagnostics, the end.
        host.sendJSON(YouTubeMessageTests.captions(videoID: secretID, events: [["t": 1.0, "d": 2.0, "text": secretWords]]))
        host.sendJSON(YouTubeMessageTests.playback(videoID: secretID, title: secretTitle))
        host.sendJSON(Self.diag("content", "content-tick-error https://www.youtube.com/watch?v=\(secretID)"))
        host.sendJSON(Self.diag("content", "content-tick-error \(secretID)"))
        host.sendJSON(Self.diag("page", "page-timedtext json3 events=1"))
        await host.waitUntilHandled()
        // The app has been tried and found away before it is there to connect to.
        #expect(await host.waitForLog(containing: "app socket unavailable"))
        try server.start()
        await waitUntil { server.frames.count >= 2 }
        host.sendJSON(YouTubeMessageTests.playback(videoID: secretID, title: secretTitle))
        host.sendJSON(["v": 1, "type": "clear", "videoId": secretID])
        host.send(Data("title=\(secretTitle) \(secretID)".utf8))
        // These are forwarded, or dropped, while the app is still there.
        await host.waitUntilHandled()
        await waitUntil { server.frames.count >= 4 }
        server.stop()
        #expect(await host.waitForLog(containing: "app socket disconnected"))
        #expect(await host.finish() == 0)

        for part in ["host start", "app socket unavailable", "extension diag", "app socket connected", "app socket disconnected", "host stdin closed", "host frames"] {
            #expect(recorder.lines.contains { $0.hasPrefix(part) }, "no line for \(part): \(recorder.lines)")
        }
        for line in recorder.lines {
            for forbidden in [secretID, secretTitle, "Zebra", "Quartz", secretWords, "hidden", "://", "youtube", "/tmp", server.directory.path, "mn-"] {
                #expect(!line.contains(forbidden), "\(line.debugDescription) holds \(forbidden)")
            }
        }
    }
}
