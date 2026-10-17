import Foundation
import Testing
@testable import YouTubeBridgeKit

/// The host looks at the socket's folder and file before it connects (`UnixStreamSocket.open`), and a refusal is handled like
/// an app that is away: nothing is written to Chrome, the host does not exit, it tries again every interval and says so in the log
/// once and then every 30 s, and what it was given for the replay is kept for the first connection it trusts.
@Suite struct YouTubeHostTrustTests {
    let server = FrameServer()
    let clock = TestClock()

    static let unavailable = "app socket unavailable reason=untrusted, trying again every 0s"

    @Test(arguments: YouTubeHostCLITests.readDelays)
    func aFolderOthersCanOpenIsNeverConnectedToAndGetsNothingUntilItIsClosedAgain(readDelay: TimeInterval) async throws {
        defer { server.remove() }
        try server.start()
        chmod(server.directory.path, 0o755)
        let host = HostRun(socketPath: server.path, clock: clock, readDelay: readDelay)
        // Captions are what a connection would replay at once, and a clear what a live one would carry.
        let captions = host.sendJSON(YouTubeHostCLITests.captions("aaaaaaaaaaa"))
        host.sendJSON(YouTubeHostCLITests.clear("bbbbbbbbbbb"))
        await host.waitForLog(containing: "app socket unavailable")
        await host.waitUntilHandled()
        // Round after round, and no connection: not even one to find out who is there.
        #expect(await host.waitForRounds(4))
        #expect(server.connectionCount == 0)
        #expect(server.frames.isEmpty)
        // What Chrome sees: nothing, and the host is still there.
        #expect(host.output.bytes.isEmpty)
        #expect(host.exitCode == nil)
        // Said once, in fixed words that hold no path.
        let said = host.logLines.filter { $0.contains("app socket") }
        #expect(said == [Self.unavailable])
        #expect(!said[0].contains("/"))

        // The same retry as for an app that is away: the next round after the folder is right connects and replays the
        // captions, and not the clear that was dropped meanwhile.
        chmod(server.directory.path, 0o700)
        await waitUntil { server.frames.count == 1 }
        #expect(server.frames == [captions])
        #expect(host.output.bytes.isEmpty)
        #expect(await host.finish() == 0)
    }

    @Test func aFolderOfAnotherUserIsNeverConnectedToAndTheReminderComesEveryThirtySeconds() async throws {
        defer { server.remove() }
        try server.start()
        // The test cannot make a folder of another user; the host is told the user is another one, which is the same check.
        let host = HostRun(socketPath: server.path, clock: clock, expectedOwner: geteuid() &+ 1)
        host.sendJSON(YouTubeHostCLITests.captions("aaaaaaaaaaa"))
        await host.waitForLog(containing: Self.unavailable)
        await host.waitUntilHandled()
        #expect(await host.waitForRounds(4))
        #expect(host.logLines.filter { $0.contains("app socket unavailable") }.count == 1)
        #expect(host.logLines.filter { $0.contains("still unavailable") }.isEmpty, "not before thirty seconds")

        clock.advance(by: 30)
        await host.waitForLog(containing: "still unavailable")
        let reminders = host.logLines.filter { $0.contains("still unavailable") }
        #expect(reminders.count == 1)
        #expect(reminders[0].hasPrefix("app socket still unavailable reason=untrusted attempts="))
        #expect(server.connectionCount == 0)
        #expect(server.frames.isEmpty)
        #expect(host.output.bytes.isEmpty)
        #expect(await host.finish() == 0)
    }

    @Test func theRunEndsWithZeroWhenTheInputEndsWhileTheFolderIsNotTrusted() async throws {
        defer { server.remove() }
        try server.start()
        chmod(server.directory.path, 0o777)
        let host = HostRun(socketPath: server.path, clock: clock)
        await host.waitForLog(containing: Self.unavailable)
        #expect(await host.finish() == 0)
        #expect(server.connectionCount == 0)
        #expect(host.output.bytes.isEmpty)
    }
}
