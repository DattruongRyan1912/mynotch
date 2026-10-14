import Foundation
import Testing
@testable import YouTubeBridgeKit

@Suite struct YouTubeMessageTests {
    static let videoID = "abcdefghijk"

    static func data(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    static func captions(
        videoID: Any = videoID, lang: Any = "vi", kind: Any = "standard", events: Any? = nil, v: Any = 1
    ) -> [String: Any] {
        ["v": v, "type": "captions", "videoId": videoID, "lang": lang, "kind": kind,
         "events": events ?? [["t": 12.34, "d": 2.1, "text": "alpha beta"]]]
    }

    static func playback(
        videoID: Any = videoID, title: Any = "Sample title", time: Any = 12.3, playing: Any = true, rate: Any = 1.0
    ) -> [String: Any] {
        ["v": 1, "type": "playback", "videoId": videoID, "title": title, "time": time, "playing": playing, "rate": rate]
    }

    static func decode(_ object: Any) -> YouTubeMessage? {
        YouTubeMessage.decode(data(object))
    }

    static func decodeCaptions(_ object: Any) -> YouTubeCaptions? {
        if case .captions(let captions) = decode(object) { captions } else { nil }
    }

    static func decodePlayback(_ object: Any) -> YouTubePlayback? {
        if case .playback(let playback) = decode(object) { playback } else { nil }
    }

    // MARK: where it comes from

    @Test func everythingButTheServiceWorkersOwnDiagnosticsIsFromThePage() {
        let videoID = Self.videoID
        let events = [CaptionEvent(time: 1, duration: 1, text: "alpha")]
        let fromPage: [YouTubeMessage] = [
            .captions(YouTubeCaptions(videoID: videoID, language: "vi", kind: .standard, events: events)),
            .playback(YouTubePlayback(videoID: videoID, title: "Sample", time: 1, isPlaying: true, rate: 1)),
            .clear(videoID: videoID),
            .diag(YouTubeDiag(origin: .content, event: "content-start")),
            .diag(YouTubeDiag(origin: .page, event: "page-seen xhr")),
        ]
        #expect(fromPage.allSatisfy { $0.isFromPage })
        #expect(!YouTubeMessage.diag(YouTubeDiag(origin: .sw, event: "sw-start v=0.1.2")).isFromPage)
        #expect(!YouTubeMessage.diag(YouTubeDiag(origin: .sw, event: "sw-access youtube=withheld")).isFromPage)
    }

    // MARK: valid messages

    @Test func aCaptionsMessageDecodesToItsFields() {
        let message = Self.decode(Self.captions(kind: "asr", events: [
            ["t": 1.5, "d": 2.0, "text": "alpha"], ["t": 4, "d": 0, "text": "beta"],
        ]))
        #expect(message == .captions(YouTubeCaptions(
            videoID: Self.videoID, language: "vi", kind: .asr,
            events: [CaptionEvent(time: 1.5, duration: 2, text: "alpha"), CaptionEvent(time: 4, duration: 0, text: "beta")]
        )))
    }

    @Test func aPlaybackMessageDecodesToItsFields() {
        #expect(Self.decode(Self.playback(time: 7.25, playing: false, rate: 1.5)) == .playback(YouTubePlayback(
            videoID: Self.videoID, title: "Sample title", time: 7.25, isPlaying: false, rate: 1.5
        )))
    }

    @Test func aClearMessageDecodesToItsVideo() {
        #expect(Self.decode(["v": 1, "type": "clear", "videoId": Self.videoID]) == .clear(videoID: Self.videoID))
    }

    @Test func unknownExtraFieldsAreIgnored() {
        var object = Self.playback()
        object["extra"] = ["nested": true]
        #expect(Self.decode(object) != nil)
    }

    // MARK: envelope

    @Test func textThatIsNoJSONObjectIsRejected() {
        #expect(YouTubeMessage.decode(Data()) == nil)
        #expect(YouTubeMessage.decode(Data("not json".utf8)) == nil)
        #expect(YouTubeMessage.decode(Data("[1,2]".utf8)) == nil)
        #expect(YouTubeMessage.decode(Data("\"clear\"".utf8)) == nil)
        #expect(YouTubeMessage.decode(Data(#"{"v":1,"type":"clear""#.utf8)) == nil)
    }

    @Test func onlyVersionOneIsAccepted() {
        for version: Any in [2, 0, "1", true, 1.5, NSNull()] {
            #expect(Self.decode(Self.captions(v: version)) == nil)
        }
        var missing = Self.captions()
        missing["v"] = nil
        #expect(Self.decode(missing) == nil)
    }

    @Test func anUnknownOrMissingTypeIsRejected() {
        #expect(Self.decode(["v": 1, "type": "seek", "videoId": Self.videoID]) == nil)
        #expect(Self.decode(["v": 1, "videoId": Self.videoID]) == nil)
        #expect(Self.decode(["v": 1, "type": 7, "videoId": Self.videoID]) == nil)
    }

    // MARK: video id

    @Test func theVideoIdIsElevenLettersDigitsDashesOrUnderscores() {
        for id in ["abcdefghijk", "AbC-dE_fG12", "-----------", "___________"] {
            #expect(Self.decode(Self.captions(videoID: id)) != nil, "\(id)")
            #expect(Self.decode(["v": 1, "type": "clear", "videoId": id]) != nil)
        }
        for id in ["", "abcdefghij", "abcdefghijkl", "abcdefghi k", "abcdefghi/k", "abcdefghiék", 12345678901] as [Any] {
            #expect(Self.decode(Self.captions(videoID: id)) == nil, "\(id)")
            #expect(Self.decode(Self.playback(videoID: id)) == nil)
            #expect(Self.decode(["v": 1, "type": "clear", "videoId": id]) == nil)
        }
        #expect(Self.decode(["v": 1, "type": "clear"]) == nil)
    }

    // MARK: captions

    @Test func theKindIsStandardOrAsr() {
        #expect(Self.decode(Self.captions(kind: "standard")) != nil)
        #expect(Self.decode(Self.captions(kind: "asr")) != nil)
        #expect(Self.decode(Self.captions(kind: "auto")) == nil)
        #expect(Self.decode(Self.captions(kind: 1)) == nil)
    }

    @Test func theLanguageIsAnInformationalString() {
        #expect(Self.decode(Self.captions(lang: "und")) != nil)
        #expect(Self.decode(Self.captions(lang: "zh-Hans")) != nil)
        #expect(Self.decode(Self.captions(lang: 5)) == nil)
        #expect(Self.decode(Self.captions(lang: String(repeating: "a", count: 40))) == nil)
    }

    @Test func eventsMustBeANonEmptyListOfAtMostFiveThousand() {
        func events(_ count: Int) -> [[String: Any]] {
            (0..<count).map { ["t": Double($0), "d": 1.0, "text": "w\($0)"] }
        }
        #expect(Self.decode(Self.captions(events: events(5_000))) != nil)
        #expect(Self.decode(Self.captions(events: events(5_001))) == nil)
        #expect(Self.decode(Self.captions(events: [] as [Any])) == nil)
        #expect(Self.decode(Self.captions(events: "alpha")) == nil)
        #expect(Self.decode(Self.captions(events: [1, 2])) == nil)
    }

    @Test func eventFieldsMustHaveTheRightTypesAndBeNonNegative() {
        let bad: [[String: Any]] = [
            ["t": "1", "d": 1, "text": "a"], ["t": 1, "d": "1", "text": "a"], ["t": 1, "d": 1, "text": 5],
            ["t": 1, "d": 1], ["d": 1, "text": "a"], ["t": 1, "text": "a"],
            ["t": -0.5, "d": 1, "text": "a"], ["t": 1, "d": -1, "text": "a"],
            ["t": true, "d": 1, "text": "a"],
        ]
        for event in bad {
            #expect(Self.decode(Self.captions(events: [event])) == nil, "\(event)")
        }
        // One bad event spoils the message, even beside good ones.
        #expect(Self.decode(Self.captions(events: [["t": 1, "d": 1, "text": "a"], ["t": -1, "d": 1, "text": "b"]])) == nil)
    }

    @Test func eventTextIsCollapsedTrimmedAndCutAtFiveHundredCharacters() throws {
        let captions = try #require(Self.decodeCaptions(Self.captions(events: [
            ["t": 1, "d": 1, "text": "  alpha\n beta\t\tgamma  "],
            ["t": 2, "d": 1, "text": String(repeating: "x", count: 600)],
            ["t": 3, "d": 1, "text": "é" + String(repeating: "y", count: 499)],
        ])))
        #expect(captions.events.map(\.text).first == "alpha beta gamma")
        #expect(captions.events[1].text == String(repeating: "x", count: 500))
        #expect(captions.events[2].text.count == 500)
    }

    @Test func eventsWithoutTextAreDroppedAndAMessageWithNoneLeftIsRejected() throws {
        let captions = try #require(Self.decodeCaptions(Self.captions(events: [
            ["t": 1, "d": 1, "text": "alpha"], ["t": 2, "d": 1, "text": "  \n "], ["t": 3, "d": 1, "text": ""],
        ])))
        #expect(captions.events.map(\.text) == ["alpha"])
        #expect(Self.decode(Self.captions(events: [["t": 1, "d": 1, "text": " "]])) == nil)
    }

    @Test func eventsComeOutSortedByTimeAndKeepTheirOrderOnATie() throws {
        let captions = try #require(Self.decodeCaptions(Self.captions(events: [
            ["t": 9, "d": 1, "text": "late"], ["t": 2, "d": 1, "text": "first"], ["t": 2, "d": 1, "text": "second"],
        ])))
        #expect(captions.events.map(\.text) == ["first", "second", "late"])
    }

    // MARK: playback

    @Test func thePlaybackTitleIsCleanedAndCut() throws {
        let long = String(repeating: "t", count: 400)
        let playback = try #require(Self.decodePlayback(Self.playback(title: "  Sample \n  title  ")))
        #expect(playback.title == "Sample title")
        let cut = try #require(Self.decodePlayback(Self.playback(title: long)))
        #expect(cut.title.count == 300)
        #expect(Self.decode(Self.playback(title: "  ")) == nil)
        #expect(Self.decode(Self.playback(title: 3)) == nil)
    }

    @Test func playbackNumbersAndFlagsAreChecked() {
        #expect(Self.decode(Self.playback(time: 0)) != nil)
        #expect(Self.decode(Self.playback(time: -1)) == nil)
        #expect(Self.decode(Self.playback(time: "1")) == nil)
        #expect(Self.decode(Self.playback(rate: 16)) != nil)
        #expect(Self.decode(Self.playback(rate: 0.25)) != nil)
        #expect(Self.decode(Self.playback(rate: 0)) == nil)
        #expect(Self.decode(Self.playback(rate: 17)) == nil)
        #expect(Self.decode(Self.playback(rate: -1)) == nil)
        #expect(Self.decode(Self.playback(playing: "true")) == nil)
        #expect(Self.decode(Self.playback(playing: 1)) == nil)
        for missing in ["title", "time", "playing", "rate"] {
            var object = Self.playback()
            object[missing] = nil
            #expect(Self.decode(object) == nil, "\(missing)")
        }
    }
}
