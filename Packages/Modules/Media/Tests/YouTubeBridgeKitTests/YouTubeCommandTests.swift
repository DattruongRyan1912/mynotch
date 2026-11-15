import Foundation
import Testing
@testable import YouTubeBridgeKit

@Suite struct YouTubeCommandTests {
    @Test func theTwoCommandsHaveOneJSONFormEach() {
        #expect(YouTubeCommand.allCases == [.next, .previous])
        #expect(String(decoding: YouTubeCommand.next.json, as: UTF8.self) == #"{"v":1,"type":"command","action":"next"}"#)
        #expect(String(decoding: YouTubeCommand.previous.json, as: UTF8.self) == #"{"v":1,"type":"command","action":"previous"}"#)
    }

    @Test func theFrameIsTheJSONInTheAppFraming() {
        for command in YouTubeCommand.allCases {
            #expect(command.frame == AppFrame.encode(command.json))
            #expect(command.frame.count - 4 <= YouTubeCommand.maxFrameLength)
        }
    }

    @Test(arguments: YouTubeCommand.allCases) func whatItEncodesToDecodesBack(command: YouTubeCommand) {
        #expect(YouTubeCommand.decode(command.json) == command)
    }

    @Test func spacingAndTheOrderOfTheFieldsDoNotMatter() {
        #expect(YouTubeCommand.decode(Data(#" { "action" : "previous" , "type":"command", "v":1 } "#.utf8)) == .previous)
        #expect(YouTubeCommand.decode(Data("{\n\"v\":1,\n\"type\":\"command\",\n\"action\":\"next\"\n}".utf8)) == .next)
    }

    @Test func nothingButTheClosedSetDecodes() {
        let refused = [
            "", "next", "null", "[]", "{}", "[\"next\"]", "not json", #"{"v":1,"type":"command","action":"next"} trailing"#,
            #"{"v":1,"type":"command"}"#,
            #"{"v":1,"action":"next"}"#,
            #"{"type":"command","action":"next"}"#,
            #"{"v":2,"type":"command","action":"next"}"#,
            #"{"v":"1","type":"command","action":"next"}"#,
            #"{"v":true,"type":"command","action":"next"}"#,
            #"{"v":1.5,"type":"command","action":"next"}"#,
            #"{"v":null,"type":"command","action":"next"}"#,
            #"{"v":1,"type":"Command","action":"next"}"#,
            #"{"v":1,"type":"command ","action":"next"}"#,
            #"{"v":1,"type":"clear","action":"next"}"#,
            #"{"v":1,"type":"command","action":"skip"}"#,
            #"{"v":1,"type":"command","action":"NEXT"}"#,
            #"{"v":1,"type":"command","action":"Next"}"#,
            #"{"v":1,"type":"command","action":" next"}"#,
            #"{"v":1,"type":"command","action":"next\n"}"#,
            #"{"v":1,"type":"command","action":""}"#,
            #"{"v":1,"type":"command","action":null}"#,
            #"{"v":1,"type":"command","action":4}"#,
            #"{"v":1,"type":"command","action":["next"]}"#,
            #"{"v":1,"type":"command","action":{"x":"next"}}"#,
            #"{"v":1,"type":"command","action":"play"}"#,
            #"{"v":1,"type":"command","action":"next","url":"https://example.invalid/"}"#,
            #"{"v":1,"type":"command","action":"next","videoId":"abcdefghijk"}"#,
            #"{"v":1,"type":"command","action":"next","extra":null}"#,
            #"{"v":1,"type":"playback","videoId":"abcdefghijk","title":"x","time":1,"playing":true,"rate":1}"#,
            #"{"v":1,"type":"diag","where":"sw","event":"sw-start v=0.1.3"}"#,
        ]
        for text in refused {
            #expect(YouTubeCommand.decode(Data(text.utf8)) == nil, "\(text)")
        }
    }

    @Test func aCommandIsNotAMessageFromTheExtension() {
        // The two directions share a connection and a framing but not a vocabulary: a command is no valid message to the app.
        #expect(YouTubeMessage.decode(YouTubeCommand.next.json) == nil)
        #expect(YouTubeMessage.check(YouTubeCommand.previous.json) == .failure(.unknownType))
    }

    @Test func theLimitLeavesRoomForACommandAndForLittleElse() {
        #expect(YouTubeCommand.maxFrameLength == 256)
    }
}
