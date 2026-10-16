import Foundation
import Testing
@testable import YouTubeBridgeKit

@Suite struct TabCommandTests {
    static let all: [TabCommand] = [
        TabCommand(tab: 5, action: .play), TabCommand(tab: 5, action: .pause), TabCommand(tab: 5, action: .toggle),
        TabCommand(tab: 5, action: .next), TabCommand(tab: 5, action: .previous), TabCommand(tab: 5, action: .seek(seconds: 61.235)),
    ]

    @Test func eachCommandHasOneJSONForm() {
        let text = Self.all.map { String(decoding: $0.json, as: UTF8.self) }
        #expect(text == [
            #"{"v":1,"type":"tabcommand","tab":5,"action":"play"}"#,
            #"{"v":1,"type":"tabcommand","tab":5,"action":"pause"}"#,
            #"{"v":1,"type":"tabcommand","tab":5,"action":"toggle"}"#,
            #"{"v":1,"type":"tabcommand","tab":5,"action":"next"}"#,
            #"{"v":1,"type":"tabcommand","tab":5,"action":"previous"}"#,
            #"{"v":1,"type":"tabcommand","tab":5,"action":"seek","seconds":61.235}"#,
        ])
    }

    @Test func aSeekIsRoundedToTheMillisecondAndHeldInRange() {
        func seconds(_ value: Double) -> String { String(decoding: TabCommand(tab: 1, action: .seek(seconds: value)).json, as: UTF8.self) }
        #expect(seconds(1.23456).hasSuffix(#""seconds":1.235}"#))
        #expect(seconds(0).hasSuffix(#""seconds":0.000}"#))
        #expect(seconds(-3).hasSuffix(#""seconds":0.000}"#))
        #expect(seconds(1e12).hasSuffix(#""seconds":10000000.000}"#))
    }

    @Test func theFrameIsTheJSONInTheAppFramingAndFitsTheHostsLimitWhateverTheNumbers() {
        for command in Self.all + [TabCommand(tab: BrowserTab.maxTabID, action: .seek(seconds: BrowserTab.maxSeconds))] {
            #expect(command.frame == AppFrame.encode(command.json))
            #expect(command.frame.count - 4 <= YouTubeCommand.maxFrameLength)
        }
    }

    @Test(arguments: all) func whatItEncodesToDecodesBack(command: TabCommand) {
        #expect(TabCommand.decode(command.json) == command)
    }

    @Test func spacingAndTheOrderOfTheFieldsDoNotMatter() {
        let text = #" { "seconds" : 3.5, "action" : "seek" , "tab":9, "type":"tabcommand", "v":1 } "#
        #expect(TabCommand.decode(Data(text.utf8)) == TabCommand(tab: 9, action: .seek(seconds: 3.5)))
    }

    @Test func nothingButTheClosedSetDecodes() {
        let refused = [
            "", "play", "null", "[]", "{}", "not json", #"{"v":1,"type":"tabcommand","tab":5,"action":"play"} trailing"#,
            #"{"v":1,"type":"tabcommand","tab":5}"#, #"{"v":1,"type":"tabcommand","action":"play"}"#, #"{"v":1,"tab":5,"action":"play"}"#,
            #"{"type":"tabcommand","tab":5,"action":"play"}"#,
            #"{"v":2,"type":"tabcommand","tab":5,"action":"play"}"#, #"{"v":"1","type":"tabcommand","tab":5,"action":"play"}"#,
            #"{"v":1,"type":"command","tab":5,"action":"play"}"#, #"{"v":1,"type":"TabCommand","tab":5,"action":"play"}"#,
            #"{"v":1,"type":"tabcommand","tab":-1,"action":"play"}"#, #"{"v":1,"type":"tabcommand","tab":2147483648,"action":"play"}"#,
            #"{"v":1,"type":"tabcommand","tab":1.5,"action":"play"}"#, #"{"v":1,"type":"tabcommand","tab":"5","action":"play"}"#,
            #"{"v":1,"type":"tabcommand","tab":null,"action":"play"}"#,
            #"{"v":1,"type":"tabcommand","tab":5,"action":"stop"}"#, #"{"v":1,"type":"tabcommand","tab":5,"action":"PLAY"}"#,
            #"{"v":1,"type":"tabcommand","tab":5,"action":" play"}"#, #"{"v":1,"type":"tabcommand","tab":5,"action":""}"#,
            #"{"v":1,"type":"tabcommand","tab":5,"action":null}"#, #"{"v":1,"type":"tabcommand","tab":5,"action":["play"]}"#,
            #"{"v":1,"type":"tabcommand","tab":5,"action":"play","url":"https://example.invalid/"}"#,
            #"{"v":1,"type":"tabcommand","tab":5,"action":"play","seconds":3}"#,
            #"{"v":1,"type":"tabcommand","tab":5,"action":"play","seconds":null}"#,
            #"{"v":1,"type":"tabcommand","tab":5,"action":"seek"}"#,
            #"{"v":1,"type":"tabcommand","tab":5,"action":"seek","seconds":null}"#,
            #"{"v":1,"type":"tabcommand","tab":5,"action":"seek","seconds":-1}"#,
            #"{"v":1,"type":"tabcommand","tab":5,"action":"seek","seconds":1e8}"#,
            #"{"v":1,"type":"tabcommand","tab":5,"action":"seek","seconds":"5"}"#,
            #"{"v":1,"type":"tabcommand","tab":5,"action":"seek","seconds":5,"url":"x"}"#,
            #"{"v":1,"type":"command","action":"next"}"#,
            #"{"v":1,"type":"playback","videoId":"abcdefghijk","title":"x","time":1,"playing":true,"rate":1}"#,
        ]
        for text in refused {
            #expect(TabCommand.decode(Data(text.utf8)) == nil, "\(text)")
        }
    }

    @Test func aYouTubeCommandIsNotATabCommandAndTheOtherWayRound() {
        for command in YouTubeCommand.allCases { #expect(TabCommand.decode(command.json) == nil) }
        for command in Self.all { #expect(YouTubeCommand.decode(command.json) == nil) }
    }

    @Test func theWordsAreTheProtocolsOwn() {
        #expect(Self.all.map(\.action.word) == ["play", "pause", "toggle", "next", "previous", "seek"])
    }
}
