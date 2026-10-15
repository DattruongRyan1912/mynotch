import Foundation
import Testing
@testable import ClipboardMCPKit

@Suite struct MCPLineFramerTests {
    private func messages(_ lines: [MCPLineFramer.Line]) -> [String] {
        lines.map {
            switch $0 {
            case .message(let data): String(decoding: data, as: UTF8.self)
            case .oversized: "<oversized>"
            }
        }
    }

    @Test func twoMessagesInOneReadComeOutSeparately() {
        var framer = MCPLineFramer()
        #expect(messages(framer.append(Data("{\"a\":1}\n{\"b\":2}\n".utf8))) == ["{\"a\":1}", "{\"b\":2}"])
    }

    @Test func aMessageInPiecesWaitsForItsNewline() {
        var framer = MCPLineFramer()
        #expect(framer.append(Data("{\"a\"".utf8)).isEmpty)
        #expect(framer.append(Data(":1".utf8)).isEmpty)
        #expect(messages(framer.append(Data("}\n{\"b\"".utf8))) == ["{\"a\":1}"])
        #expect(messages(framer.append(Data(":2}\n".utf8))) == ["{\"b\":2}"])
    }

    @Test func aCharacterSplitBetweenReadsArrivesWhole() {
        var framer = MCPLineFramer()
        let bytes = Array("\"đ\"\n".utf8)
        #expect(framer.append(Data(bytes[0..<2])).isEmpty)
        #expect(messages(framer.append(Data(bytes[2...]))) == ["\"đ\""])
    }

    @Test func oneByteAtATimeGivesTheSameMessages() {
        var framer = MCPLineFramer()
        var found: [MCPLineFramer.Line] = []
        for byte in Array("{\"a\":1}\n\n{\"b\":2}\r\n".utf8) { found += framer.append(Data([byte])) }
        #expect(messages(found) == ["{\"a\":1}", "{\"b\":2}"])
    }

    @Test func blankLinesAndACarriageReturnAreNotMessages() {
        var framer = MCPLineFramer()
        #expect(messages(framer.append(Data("\n\r\n  \n{\"a\":1}\r\n".utf8))) == ["{\"a\":1}"])
    }

    @Test func aLineOverTheLimitIsReportedOnceAndSkippedToItsEnd() {
        var framer = MCPLineFramer(maxLength: 8)
        #expect(messages(framer.append(Data("0123456789".utf8))) == ["<oversized>"])
        // The rest of that line, however long, is dropped; only the next line is read.
        #expect(framer.append(Data("0123456789".utf8)).isEmpty)
        #expect(messages(framer.append(Data("0123\n{\"a\":1}\n".utf8))) == ["{\"a\":1}"])
    }

    @Test func aLineOfExactlyTheLimitIsKept() {
        var framer = MCPLineFramer(maxLength: 8)
        #expect(messages(framer.append(Data("12345678\n".utf8))) == ["12345678"])
    }

    @Test func aLineLongerThanTheLimitInOneReadIsSkippedToo() {
        var framer = MCPLineFramer(maxLength: 4)
        #expect(messages(framer.append(Data("0123456789\nok\n".utf8))) == ["<oversized>", "ok"])
    }

    @Test func whatIsLeftWhenTheInputEndsIsAMessage() {
        var framer = MCPLineFramer()
        #expect(framer.append(Data("{\"a\":1}".utf8)).isEmpty)
        #expect(messages(framer.finish()) == ["{\"a\":1}"])
        #expect(framer.finish().isEmpty)
    }
}
