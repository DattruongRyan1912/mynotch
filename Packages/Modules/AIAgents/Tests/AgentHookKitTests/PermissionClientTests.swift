import Foundation
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
        let path = "/tmp/mn-\(UUID().uuidString.prefix(8))/perm.sock"
        var outcome: PermissionClient.Outcome?
        let seconds = elapsed { outcome = PermissionClient.ask(request, socketPath: path, timeout: 30) }
        #expect(outcome == .unreachable)
        #expect(seconds < 8)
    }

    @Test func aSocketFileNobodyListensOnIsUnreachable() throws {
        let directory = "/tmp/mn-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        try Data("stale".utf8).write(to: URL(filePath: directory + "/perm.sock"))
        #expect(PermissionClient.ask(request, socketPath: directory + "/perm.sock", timeout: 30) == .unreachable)
    }

    @Test func aPathThatDoesNotFitAndARequestThatCannotBeMadeAreUnreachable() throws {
        #expect(PermissionClient.ask(request, socketPath: String(repeating: "a", count: 300), timeout: 30) == .unreachable)
        var big = request
        big.tool = String(repeating: "t", count: 5_000)
        let app = try FakePermissionApp(behavior: .reply(#"{"decision":"allow"}"# + "\n"))
        #expect(PermissionClient.ask(big, socketPath: app.socketPath, timeout: 30) == .unreachable)
        #expect(app.connectionCount == 0)
    }

    @Test func aPeerThatClosesAsSoonAsItIsReachedIsNoAnswerEveryTimeAndNeverACrash() throws {
        let app = try FakePermissionApp(behavior: .hangUp)
        for _ in 0..<20 { #expect(PermissionClient.ask(request, socketPath: app.socketPath, timeout: 0.5) == .noAnswer) }
    }
}
