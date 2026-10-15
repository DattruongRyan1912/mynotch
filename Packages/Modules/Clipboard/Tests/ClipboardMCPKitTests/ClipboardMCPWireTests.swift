import Foundation
import Testing
@testable import ClipboardMCPKit

@Suite struct ClipboardMCPWireTests {
    @Test func aRequestIsOneLineThatReadsBackTheSame() throws {
        let request = ClipboardMCPRequest.search(ClipboardMCPSearch(query: "a\nb", kind: .link, limit: 3))
        let line = try #require(ClipboardMCPWire.requestLine(request))
        #expect(line.last == UInt8(ascii: "\n"))
        #expect(line.dropLast().contains(UInt8(ascii: "\n")) == false)
        #expect(ClipboardMCPWire.decodeRequest(line.dropLast()) == .request(request))
    }

    @Test func aRequestOfAnotherShapeIsUnreadable() {
        for text in [
            #"{"arguments":{"query":"x"},"tool":"search_clipboard"}"#,
            #"{"arguments":[],"tool":"search_clipboard","version":1}"#,
            #"{"arguments":{"query":"x"},"tool":3,"version":1}"#,
            #"[1]"#, "nonsense", "",
        ] {
            #expect(ClipboardMCPWire.decodeRequest(Data(text.utf8)) == .unreadable, "\(text)")
        }
    }

    @Test func aRequestOfAnotherVersionIsRefusedWithItsReason() {
        let line = Data(#"{"arguments":{"query":"x"},"tool":"search_clipboard","version":2}"#.utf8)
        guard case .rejected(let reason, let message) = ClipboardMCPWire.decodeRequest(line) else {
            Issue.record("not rejected")
            return
        }
        #expect(reason == .versionMismatch)
        #expect(message.contains("mynotch-clipboard-mcp"))
    }

    @Test func aRequestThatBreaksTheArgumentRulesIsRefusedAndSaysHow() {
        // The app asks again whether the arguments are good, since it does not trust the helper to have asked.
        let bad = Data(#"{"arguments":{"query":"x","limit":500},"tool":"search_clipboard","version":1}"#.utf8)
        #expect(ClipboardMCPWire.decodeRequest(bad) == .rejected(.invalidArguments, "limit must be a whole number from 1 to 50"))
        let unknown = Data(#"{"arguments":{},"tool":"drop_table","version":1}"#.utf8)
        #expect(ClipboardMCPWire.decodeRequest(unknown) == .rejected(.invalidArguments, "Unknown tool: drop_table"))
    }

    @Test func aRequestOverTheLimitIsUnreadable() throws {
        let text = String(repeating: "a", count: ClipboardMCPWire.maxRequestLength)
        let line = Data(#"{"arguments":{"query":"\#(text)"},"tool":"search_clipboard","version":1}"#.utf8)
        #expect(ClipboardMCPWire.decodeRequest(line) == .unreadable)
    }

    @Test func anAnswerWithResultsReadsBackTheSame() throws {
        let reply = ClipboardMCPWireReply.success(.object(["count": .int(2), "items": .array([])]))
        let line = try #require(ClipboardMCPWire.replyLine(reply))
        #expect(line.last == UInt8(ascii: "\n"))
        #expect(ClipboardMCPWire.decodeReply(line.dropLast()) == reply)
    }

    @Test func aRefusalCarriesItsReasonAndMessage() throws {
        for reason in ClipboardMCPFailure.allCases {
            let reply = ClipboardMCPWireReply.failure(reason, "msg \(reason.rawValue)")
            let line = try #require(ClipboardMCPWire.replyLine(reply))
            #expect(ClipboardMCPWire.decodeReply(line.dropLast()) == reply)
        }
        #expect(Set(ClipboardMCPFailure.allCases.map(\.rawValue)) == ["disabled", "rateLimited", "invalidArguments", "notFound", "versionMismatch", "failed"])
    }

    @Test func anAnswerThatIsNeitherAResultNorAFailureIsNotRead() {
        for text in [#"{"ok":true}"#, #"{"ok":false}"#, #"{"ok":false,"failure":"unknown","message":"m"}"#, "{}", "x"] {
            #expect(ClipboardMCPWire.decodeReply(Data(text.utf8)) == nil, "\(text)")
        }
    }
}
