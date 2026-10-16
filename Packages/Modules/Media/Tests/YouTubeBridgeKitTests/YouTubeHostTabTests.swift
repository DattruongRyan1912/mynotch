import Foundation
import Testing
@testable import YouTubeBridgeKit

/// What the host does for the pages that have media: it passes their reports on, keeps the latest of each for an app that comes
/// later, and writes the app's commands for a tab to Chrome.
@Suite struct YouTubeHostTabTests {
    let server = FrameServer()
    let clock = TestClock()

    static func tab(_ tab: Int, title: String = "Song", state: String = "playing") -> [String: Any] {
        BrowserTabMessageTests.tab(tab: tab, title: title, state: state)
    }

    static func gone(_ tab: Int) -> [String: Any] {
        ["v": 1, "type": "tabgone", "tab": tab]
    }

    func start(readDelay: TimeInterval = 0) -> HostRun {
        HostRun(socketPath: server.path, clock: clock, readDelay: readDelay)
    }

    // MARK: forwarding

    @Test func everyReportAndEveryGoneIsForwardedAsTheSameBytesInOrder() async throws {
        defer { server.remove() }
        try server.start()
        let host = start()
        await waitUntil { server.connectionCount == 1 }
        let sent = [
            host.sendJSON(Self.tab(7)), host.sendJSON(Self.tab(8, state: "paused")), host.sendJSON(Self.gone(7)),
        ]
        await waitUntil { server.frames.count == 3 }
        #expect(server.frames == sent)
        #expect(await host.finish() == 0)
    }

    @Test func aReportThatIsNotValidIsDroppedAndNeverKept() async throws {
        defer { server.remove() }
        let host = start()
        host.sendJSON(Self.tab(-1))
        host.sendJSON(BrowserTabMessageTests.tab(title: ""))
        host.sendJSON(["v": 1, "type": "tabgone", "tab": "x"])
        await host.waitUntilHandled()
        try server.start()
        await host.waitForLog(containing: "app socket connected replayed-captions=0 replayed-playback=false")
        #expect(server.frames.isEmpty)
        #expect(await host.finish() == 0)
    }

    // MARK: replay

    @Test(arguments: YouTubeHostCLITests.readDelays) func theLatestReportOfEachPageIsReplayedAfterWhatTheCaptionsNeed(readDelay: TimeInterval) async throws {
        defer { server.remove() }
        let host = start(readDelay: readDelay)
        host.sendJSON(Self.tab(7, title: "Old"))
        let other = host.sendJSON(Self.tab(8))
        let captions = host.sendJSON(YouTubeHostCLITests.captions("aaaaaaaaaaa"))
        let latest = host.sendJSON(Self.tab(7, title: "New"))
        await host.waitUntilHandled()
        try server.start()
        await host.waitForLog(containing: "app socket connected replayed-captions=1 replayed-playback=false replayed-tabs=2")
        await waitUntil { server.frames.count == 3 }
        #expect(server.frames == [captions, other, latest], "the captions first, then each page's latest report, the least recent first")
        // New reports follow the replay.
        let after = host.sendJSON(Self.tab(9))
        await waitUntil { server.frames.count == 4 }
        #expect(server.frames.last == after)
        #expect(await host.finish() == 0)
    }

    @Test(arguments: YouTubeHostCLITests.readDelays) func aPageThatSaidItHasNoMediaIsNotReplayed(readDelay: TimeInterval) async throws {
        defer { server.remove() }
        let host = start(readDelay: readDelay)
        host.sendJSON(Self.tab(7))
        let kept = host.sendJSON(Self.tab(8))
        host.sendJSON(Self.gone(7))
        await host.waitUntilHandled()
        try server.start()
        await host.waitForLog(containing: "replayed-tabs=1")
        await waitUntil { !server.frames.isEmpty }
        #expect(server.frames == [kept])
        #expect(await host.finish() == 0)
    }

    @Test(arguments: YouTubeHostCLITests.readDelays) func aReportOlderThanTheAppsMemoryOfAPageIsNotReplayed(readDelay: TimeInterval) async throws {
        defer { server.remove() }
        let host = start(readDelay: readDelay)
        host.sendJSON(Self.tab(7))
        await host.waitUntilHandled()
        clock.advance(by: 100)
        let fresh = host.sendJSON(Self.tab(8))
        await host.waitUntilHandled()
        clock.advance(by: HostRelay.maxTabAge - 100 + 1) // the first is now past the limit, the second is not
        try server.start()
        await host.waitForLog(containing: "replayed-tabs=1")
        await waitUntil { !server.frames.isEmpty }
        #expect(server.frames == [fresh])
        #expect(await host.finish() == 0)
    }

    @Test func atMostSixtyFourPagesAreKeptTheOldestGoingFirst() async throws {
        defer { server.remove() }
        // No late reader here: it would make the host wait 0.15 s for each of the many messages.
        let host = start()
        var sent: [Data] = []
        for tab in 0..<(HostRelay.maxTabs + 3) { sent.append(host.sendJSON(Self.tab(tab))) }
        await host.waitUntilHandled()
        try server.start()
        await host.waitForLog(containing: "replayed-tabs=\(HostRelay.maxTabs)")
        await waitUntil { server.frames.count == HostRelay.maxTabs }
        #expect(server.frames == Array(sent.suffix(HostRelay.maxTabs)))
        #expect(await host.finish() == 0)
    }

    @Test(arguments: YouTubeHostCLITests.readDelays) func aRestartedAppGetsTheReportsAgain(readDelay: TimeInterval) async throws {
        defer { server.remove() }
        try server.start()
        let host = start(readDelay: readDelay)
        await waitUntil { server.connectionCount == 1 }
        let report = host.sendJSON(Self.tab(7))
        await waitUntil { server.frames.count == 1 }
        server.stop()
        await host.waitForLog(containing: "app socket disconnected")

        let restarted = FrameServer(directory: server.directory)
        try restarted.start()
        await waitUntil { restarted.frames.count == 1 }
        #expect(restarted.frames == [report])
        restarted.stop()
        #expect(await host.finish() == 0)
    }

    @Test(arguments: YouTubeHostCLITests.readDelays) func theLogLineSaysNothingOfPagesWhenThereAreNone(readDelay: TimeInterval) async throws {
        defer { server.remove() }
        let host = start(readDelay: readDelay)
        host.sendJSON(YouTubeHostCLITests.captions("aaaaaaaaaaa"))
        await host.waitUntilHandled()
        try server.start()
        await host.waitForLog(containing: "app socket connected replayed-captions=1 replayed-playback=false")
        #expect(!host.logLines.contains { $0.contains("replayed-tabs") })
        #expect(await host.finish() == 0)
    }

    @Test func noLineOfTheLogHoldsAPageOrAWord() async throws {
        defer { server.remove() }
        let host = start()
        host.sendJSON(BrowserTabMessageTests.tab(site: "secret.example.com", title: "My Secret Song", artist: "Secret Artist"))
        await host.waitUntilHandled()
        try server.start()
        await host.waitForLog(containing: "replayed-tabs=1")
        let log = host.logLines.joined(separator: "\n")
        for secret in ["Secret", "secret", "Song"] { #expect(!log.contains(secret), Comment(rawValue: secret)) }
        #expect(await host.finish() == 0)
    }

    // MARK: commands for a tab

    @Test func aCommandForATabIsWrittenToChromeAsANativeMessageAndNothingElse() async throws {
        defer { server.remove() }
        try server.start()
        let host = start()
        await waitUntil { server.connectionCount == 1 }
        let commands = TabCommandTests.all
        for command in commands { server.sendFrame(command.json) }
        await waitUntil { host.output.messages.count == commands.count }
        #expect(host.output.messages == commands.map(\.json))
        #expect(host.output.bytes == commands.reduce(into: Data()) { $0 += nativeFrame($1.json) })
        #expect(host.logLines.filter { $0.hasPrefix("command forwarded") }
            == ["play", "pause", "toggle", "next", "previous", "seek"].map { "command forwarded tab-action=\($0)" })
        #expect(await host.finish() == 0)
    }

    @Test func theHostWritesTheCheckedTabCommandAndNotTheBytesItWasGiven() async throws {
        defer { server.remove() }
        try server.start()
        let host = start()
        await waitUntil { server.connectionCount == 1 }
        server.sendFrame(Data(#" { "seconds":30.00049, "action": "seek",  "tab":4, "type":"tabcommand", "v":1 } "#.utf8))
        await waitUntil { !host.output.messages.isEmpty }
        #expect(host.output.messages == [TabCommand(tab: 4, action: .seek(seconds: 30.00049)).json])
        #expect(String(decoding: host.output.messages[0], as: UTF8.self).contains(#""seconds":30.000}"#))
        #expect(await host.finish() == 0)
    }

    @Test func aTabCommandBetweenOthersAndOneCommandInPiecesAreAllForwardedInOrder() async throws {
        defer { server.remove() }
        try server.start()
        let host = start()
        await waitUntil { server.connectionCount == 1 }
        server.sendFrame(YouTubeCommand.next.json)
        let bytes = TabCommand(tab: 3, action: .pause).frame + TabCommand(tab: 3, action: .seek(seconds: 9)).frame
        for start in stride(from: 0, to: bytes.count, by: 7) {
            server.send(bytes[start..<min(start + 7, bytes.count)])
            try await Task.sleep(for: .milliseconds(2))
        }
        server.sendFrame(YouTubeCommand.previous.json)
        await waitUntil { host.output.messages.count == 4 }
        #expect(host.output.messages == [
            YouTubeCommand.next.json, TabCommand(tab: 3, action: .pause).json, TabCommand(tab: 3, action: .seek(seconds: 9)).json,
            YouTubeCommand.previous.json,
        ])
        #expect(await host.finish() == 0)
    }

    @Test func aTabCommandThatIsNotInTheClosedSetIsDroppedAndTheConnectionGoesOn() async throws {
        defer { server.remove() }
        try server.start()
        let host = start()
        await waitUntil { server.connectionCount == 1 }
        let refused = [
            #"{"v":1,"type":"tabcommand","tab":5,"action":"stop"}"#,
            #"{"v":1,"type":"tabcommand","tab":-1,"action":"play"}"#,
            #"{"v":1,"type":"tabcommand","tab":5,"action":"play","url":"https://example.invalid/"}"#,
            #"{"v":1,"type":"tabcommand","tab":5,"action":"seek"}"#,
            #"{"v":1,"type":"tabcommand","tab":5,"action":"play","seconds":3}"#,
            #"{"v":2,"type":"tabcommand","tab":5,"action":"play"}"#,
            #"{"v":1,"type":"tab","tab":5,"site":"x.com","title":"x","state":"playing","time":1,"rate":1,"live":false}"#,
        ]
        for text in refused { server.sendFrame(Data(text.utf8)) }
        server.sendFrame(TabCommand(tab: 5, action: .play).json)
        await waitUntil { !host.output.messages.isEmpty }
        #expect(host.output.messages == [TabCommand(tab: 5, action: .play).json])
        #expect(host.logLines.filter { $0 == "command dropped reason=invalid" }.count == refused.count)
        #expect(server.connectionCount == 1)
        #expect(await host.finish() == 0)
    }

    @Test func aPipeChromeHasClosedCostsTheTabCommandAndNothingElse() async throws {
        defer { server.remove() }
        try server.start()
        let host = start()
        await waitUntil { server.connectionCount == 1 }
        host.output.fails = true
        server.sendFrame(TabCommand(tab: 5, action: .play).json)
        await host.waitForLog(containing: "command not delivered")
        #expect(host.output.bytes.isEmpty)
        host.output.fails = false
        server.sendFrame(TabCommand(tab: 5, action: .pause).json)
        await waitUntil { !host.output.messages.isEmpty }
        #expect(host.output.messages == [TabCommand(tab: 5, action: .pause).json])
        #expect(await host.finish() == 0)
    }
}
