import Foundation
import Testing
@testable import ClipboardMCPKit

@Suite struct ClipboardMCPClientTests {
    let request = ClipboardMCPRequest.search(ClipboardMCPSearch(query: "invoice", kind: .link, limit: 5))
    let answer = ClipboardMCPWireReply.success(.object(["count": .int(0), "items": .array([])]))

    var answerLine: String { String(decoding: ClipboardMCPWire.replyLine(answer) ?? Data(), as: UTF8.self) }

    /// How long `body` ran, in seconds.
    func elapsed(_ body: () -> Void) -> TimeInterval {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
    }

    @Test func theAppsAnswerComesBack() throws {
        let app = try FakeMCPApp(behavior: .reply(answerLine))
        #expect(ClipboardMCPClient.send(request, socketPath: app.socketPath, timeout: 30) == .reply(answer))
    }

    @Test func aRefusalComesBackWithItsReason() throws {
        let refusal = ClipboardMCPWireReply.failure(.disabled, "off")
        let app = try FakeMCPApp(behavior: .reply(String(decoding: ClipboardMCPWire.replyLine(refusal) ?? Data(), as: UTF8.self)))
        #expect(ClipboardMCPClient.send(request, socketPath: app.socketPath, timeout: 30) == .reply(refusal))
    }

    @Test func theAppReceivesTheRequestAsOneLine() throws {
        let app = try FakeMCPApp(behavior: .reply(answerLine))
        _ = ClipboardMCPClient.send(request, socketPath: app.socketPath, timeout: 30)
        let received = try #require(app.requests.first)
        #expect(app.requests.count == 1)
        #expect(ClipboardMCPWire.decodeRequest(received) == .request(request))
    }

    @Test func aReplyInPiecesIsAssembled() throws {
        let line = answerLine
        let app = try FakeMCPApp(behavior: .replyInPieces(String(line.prefix(10)), String(line.dropFirst(10))))
        #expect(ClipboardMCPClient.send(request, socketPath: app.socketPath, timeout: 30) == .reply(answer))
    }

    @Test func aReplyWithoutANewlineBeforeTheAppClosesIsStillRead() throws {
        let app = try FakeMCPApp(behavior: .reply(String(answerLine.dropLast())))
        #expect(ClipboardMCPClient.send(request, socketPath: app.socketPath, timeout: 30) == .reply(answer))
    }

    @Test func noAnswerInTimeIsNoAnswerAndTheWaitIsBounded() throws {
        let app = try FakeMCPApp(behavior: .silent)
        var outcome: ClipboardMCPClient.Outcome?
        let seconds = elapsed { outcome = ClipboardMCPClient.send(request, socketPath: app.socketPath, timeout: 0.4) }
        #expect(outcome == .noAnswer)
        #expect(seconds >= 0.35)
        #expect(seconds < 8)
    }

    @Test func anAppThatNeverReadsTheRequestIsWaitedForOnlyUntilTheTimeout() throws {
        let app = try FakeMCPApp(behavior: .ignore)
        var outcome: ClipboardMCPClient.Outcome?
        let seconds = elapsed { outcome = ClipboardMCPClient.send(request, socketPath: app.socketPath, timeout: 0.3) }
        #expect(outcome == .noAnswer)
        #expect(seconds < 8)
    }

    @Test func anAppThatHangsUpIsNoAnswerAtOnce() throws {
        let app = try FakeMCPApp(behavior: .hangUp)
        var outcome: ClipboardMCPClient.Outcome?
        let seconds = elapsed { outcome = ClipboardMCPClient.send(request, socketPath: app.socketPath, timeout: 30) }
        #expect(outcome == .noAnswer)
        #expect(seconds < 8)
    }

    @Test func aReplyThatIsNotAnAnswerIsNoAnswer() throws {
        for reply in ["garbage\n", "\n", #"{"ok":true}"# + "\n", #"{"ok":false,"failure":"x","message":"m"}"# + "\n"] {
            let app = try FakeMCPApp(behavior: .reply(reply))
            #expect(ClipboardMCPClient.send(request, socketPath: app.socketPath, timeout: 30) == .noAnswer, "\(reply)")
        }
    }

    @Test func aReplyThatNeverEndsIsNoAnswerOnceItPassesTheLimit() throws {
        let app = try FakeMCPApp(behavior: .reply(String(repeating: "a", count: ClipboardMCPWire.maxReplyLength + 1_000)))
        #expect(ClipboardMCPClient.send(request, socketPath: app.socketPath, timeout: 30) == .noAnswer)
    }

    @Test func noAppMeansUnreachableAtOnce() {
        var outcome: ClipboardMCPClient.Outcome?
        let seconds = elapsed {
            outcome = ClipboardMCPClient.send(request, socketPath: "/tmp/mn-\(UUID().uuidString.prefix(8))/mcp.sock", timeout: 30)
        }
        #expect(outcome == .unreachable)
        #expect(seconds < 8)
    }

    @Test func aSocketFileNobodyListensOnIsUnreachable() throws {
        let folder = try SocketFolder()
        try folder.bindSocket()
        folder.stopListening()
        #expect(ClipboardMCPClient.send(request, socketPath: folder.socketPath, timeout: 30) == .unreachable)
    }

    @Test func aFileThatIsNotASocketIsNotTalkedTo() throws {
        let folder = try SocketFolder()
        try Data("stale".utf8).write(to: URL(filePath: folder.socketPath))
        #expect(ClipboardMCPClient.send(request, socketPath: folder.socketPath, timeout: 30) == .untrusted)
    }

    @Test func aPathThatDoesNotFitIsUnreachable() {
        #expect(ClipboardMCPClient.send(request, socketPath: String(repeating: "a", count: 300), timeout: 30) == .unreachable)
    }

    // MARK: Who is on the other end

    @Test func aListenerOfAnotherUserIsNeverSentTheRequestNorBelieved() throws {
        let app = try FakeMCPApp(behavior: .reply(answerLine))
        // The fake runs as this user; asking for another one is what meeting a listener of another user looks like.
        let outcome = ClipboardMCPClient.send(request, socketPath: app.socketPath, timeout: 30, trustedUser: geteuid() &+ 1)
        #expect(outcome == .untrusted)
        #expect(app.connectionCount == 0)
        #expect(app.requests.isEmpty)
    }

    @Test func aFolderOthersCanOpenIsNeverTalkedTo() throws {
        for mode in [0o755, 0o770, 0o777] {
            let app = try FakeMCPApp(behavior: .reply(answerLine), folderMode: mode)
            #expect(ClipboardMCPClient.send(request, socketPath: app.socketPath, timeout: 30) == .untrusted, "mode \(String(mode, radix: 8))")
            #expect(app.connectionCount == 0)
        }
    }

    @Test func aPeerThatIsNotTheUserIsGivenNothingEvenWhenTheFolderLooksRight() throws {
        let app = try FakeMCPApp(behavior: .reply(answerLine))
        let outcome = ClipboardMCPClient.send(request, socketPath: app.socketPath, timeout: 30, trustedUser: geteuid(), peerUser: geteuid() &+ 1)
        #expect(outcome == .untrusted)
        // It connected, to look at who it was, and wrote nothing.
        #expect(app.requests.isEmpty)
    }

    @Test func aPeerThatClosesAsSoonAsItIsReachedIsNoAnswerEveryTimeAndNeverACrash() throws {
        let app = try FakeMCPApp(behavior: .hangUp)
        for _ in 0..<20 { #expect(ClipboardMCPClient.send(request, socketPath: app.socketPath, timeout: 0.5) == .noAnswer) }
    }
}
