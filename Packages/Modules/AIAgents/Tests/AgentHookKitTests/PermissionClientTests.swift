import Foundation
import LocalSocketKit
import MyNotchTestSupport
import Testing
@testable import AgentHookKit

@Suite struct PermissionClientTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    var request: HookPayload {
        HookPayload(source: "claude", event: "PermissionRequest", sessionID: "s1", cwd: "/p", tool: "Bash", summary: "ls", timestamp: now)
    }

    /// How long `body` ran, in seconds.
    func elapsed(_ body: () -> Void) -> TimeInterval {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    }

    @Test func theAppsAnswerComesBack() throws {
        for (reply, expected) in [
            (#"{"decision":"allow"}"# + "\n", PermissionAnswer.allow), (#"{"decision":"deny"}"# + "\n", .deny), (#"{"decision":"ask"}"# + "\n", .ask),
        ] {
            let app = try FakePermissionApp(behavior: .reply(reply))
            #expect(PermissionClient.ask(request, socketPath: app.socketPath, timeout: 30) == .answered(expected))
        }
    }

    @Test func theAppReceivesTheRequestAsOneLine() throws {
        let app = try FakePermissionApp(behavior: .reply(#"{"decision":"allow"}"# + "\n"))
        _ = PermissionClient.ask(request, socketPath: app.socketPath, timeout: 30)
        #expect(app.requests.count == 1)
        #expect(PermissionWire.decodeRequest(app.requests[0]) == request)
    }

    @Test func aReplyInPiecesIsAssembled() throws {
        let app = try FakePermissionApp(behavior: .replyInPieces(#"{"decision":"#, #""deny"}"# + "\n"))
        #expect(PermissionClient.ask(request, socketPath: app.socketPath, timeout: 30) == .answered(.deny))
    }

    @Test func aReplyWithoutANewlineBeforeTheAppClosesIsStillRead() throws {
        let app = try FakePermissionApp(behavior: .reply(#"{"decision":"allow"}"#))
        #expect(PermissionClient.ask(request, socketPath: app.socketPath, timeout: 30) == .answered(.allow))
    }

    @Test func noAnswerInTimeIsNoAnswerAndTheWaitIsBounded() throws {
        let app = try FakePermissionApp(behavior: .silent)
        var outcome: PermissionClient.Outcome?
        let seconds = elapsed { outcome = PermissionClient.ask(request, socketPath: app.socketPath, timeout: 0.4) }
        #expect(outcome == .noAnswer)
        #expect(seconds >= 0.35)
        #expect(seconds < 8)
    }

    @Test func anAppThatNeverReadsTheRequestIsWaitedForOnlyUntilTheTimeout() throws {
        let app = try FakePermissionApp(behavior: .ignore)
        var outcome: PermissionClient.Outcome?
        let seconds = elapsed { outcome = PermissionClient.ask(request, socketPath: app.socketPath, timeout: 0.3) }
        #expect(outcome == .noAnswer)
        #expect(seconds < 8)
    }

    @Test func anAppThatHangsUpIsNoAnswerAtOnce() throws {
        let app = try FakePermissionApp(behavior: .hangUp)
        var outcome: PermissionClient.Outcome?
        let seconds = elapsed { outcome = PermissionClient.ask(request, socketPath: app.socketPath, timeout: 30) }
        #expect(outcome == .noAnswer)
        #expect(seconds < 8)
    }

    @Test func aMalformedReplyIsNoAnswer() throws {
        for reply in ["garbage\n", #"{"decision":"maybe"}"# + "\n", "\n", #"{"decision":"allow""# + "\n"] {
            let app = try FakePermissionApp(behavior: .reply(reply))
            #expect(PermissionClient.ask(request, socketPath: app.socketPath, timeout: 30) == .noAnswer, "\(reply)")
        }
    }

    @Test func aReplyThatNeverEndsIsNoAnswer() throws {
        let app = try FakePermissionApp(behavior: .reply(String(repeating: "a", count: 10_000)))
        #expect(PermissionClient.ask(request, socketPath: app.socketPath, timeout: 30) == .noAnswer)
    }

    @Test func noAppMeansUnreachableAtOnce() {
        let path = SocketFolder.reservedPath() + "/perm.sock"
        var outcome: PermissionClient.Outcome?
        let seconds = elapsed { outcome = PermissionClient.ask(request, socketPath: path, timeout: 30) }
        #expect(outcome == .unreachable)
        #expect(seconds < 8)
    }

    @Test func aSocketFileNobodyListensOnIsUnreachable() throws {
        let folder = try SocketFolder(socketName: "perm.sock")
        // What a crashed app leaves: the socket file, with nothing behind it.
        try folder.bindSocket()
        folder.stopListening()
        #expect(PermissionClient.ask(request, socketPath: folder.socketPath, timeout: 30) == .unreachable)
    }

    @Test func aFileThatIsNotASocketIsNotTalkedTo() throws {
        let folder = try SocketFolder(socketName: "perm.sock")
        try Data("stale".utf8).write(to: URL(filePath: folder.socketPath))
        #expect(PermissionClient.ask(request, socketPath: folder.socketPath, timeout: 30) == .untrusted)
    }

    @Test func aPathThatDoesNotFitAndARequestThatCannotBeMadeAreUnreachable() throws {
        #expect(PermissionClient.ask(request, socketPath: String(repeating: "a", count: 300), timeout: 30) == .unreachable)
        var big = request
        big.tool = String(repeating: "t", count: 2 * PermissionWire.maxRequestLength)
        let app = try FakePermissionApp(behavior: .reply(#"{"decision":"allow"}"# + "\n"))
        #expect(PermissionClient.ask(big, socketPath: app.socketPath, timeout: 30) == .unreachable)
        #expect(app.connectionCount == 0)
    }

    @Test func aPeerThatClosesAsSoonAsItIsReachedIsNoAnswerEveryTimeAndNeverACrash() throws {
        let app = try FakePermissionApp(behavior: .hangUp)
        for _ in 0..<20 { #expect(PermissionClient.ask(request, socketPath: app.socketPath, timeout: 0.5) == .noAnswer) }
    }

    // MARK: Who is on the other end

    /// The app answers "allow" to anything: only the check of who it is stands between that and the agent.
    let allowAnything = #"{"decision":"allow"}"# + "\n"

    @Test func aListenerOfAnotherUserIsNeverSentTheRequestNorBelieved() throws {
        let app = try FakePermissionApp(behavior: .reply(allowAnything))
        // The fake runs as this user; asking for another one is what meeting a listener of another user looks like.
        let outcome = PermissionClient.ask(request, socketPath: app.socketPath, timeout: 30, trustedUser: geteuid() &+ 1)
        #expect(outcome == .untrusted)
        #expect(app.connectionCount == 0)
        #expect(app.requests.isEmpty)
    }

    @Test func aFolderOthersCanOpenIsNeverTalkedTo() throws {
        for mode in [0o755, 0o770, 0o777] {
            let app = try FakePermissionApp(behavior: .reply(allowAnything), folderMode: mode)
            #expect(PermissionClient.ask(request, socketPath: app.socketPath, timeout: 30) == .untrusted, "mode \(String(mode, radix: 8))")
            #expect(app.connectionCount == 0)
        }
    }

    @Test func aPeerThatIsNotTheUserIsGivenNothingEvenWhenTheFolderLooksRight() throws {
        let app = try FakePermissionApp(behavior: .reply(allowAnything))
        // The files are the user's; only the connected process is not, as for a listener started by another user in a
        // folder that was made for the user in some other way.
        #expect(SocketTrust.inspect(socketPath: app.socketPath) == .trusted)
        let outcome = PermissionClient.ask(request, socketPath: app.socketPath, timeout: 30, trustedUser: geteuid(), peerUser: geteuid() &+ 1)
        #expect(outcome == .untrusted)
        // The connection was made and dropped before a byte was written.
        let deadline = Date().addingTimeInterval(5)
        while app.servedCount < 1, Date() < deadline { usleep(10_000) }
        #expect(app.servedCount == 1)
        #expect(app.requests.isEmpty)
    }
}
