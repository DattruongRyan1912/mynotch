import Foundation
import Testing
@testable import YouTubeBridgeKit

/// Why a message is refused, as a fixed code for the logs: nothing of the message itself is in it.
@Suite struct YouTubeMessageRejectionTests {
    func rejection(_ object: Any) -> YouTubeMessage.Rejection? {
        if case .failure(let rejection) = YouTubeMessage.check(YouTubeMessageTests.data(object)) { rejection } else { nil }
    }

    @Test func aValidMessageHasNoRejection() {
        #expect(rejection(YouTubeMessageTests.playback()) == nil)
        #expect(YouTubeMessage.check(YouTubeMessageTests.data(YouTubeMessageTests.playback())) == .success(.playback(YouTubePlayback(
            videoID: YouTubeMessageTests.videoID, title: "Sample title", time: 12.3, isPlaying: true, rate: 1
        ))))
    }

    @Test func notJSONOrWithoutAVersionAndTypeIsMalformed() {
        #expect(YouTubeMessage.check(Data("not json".utf8)) == .failure(.malformed))
        #expect(YouTubeMessage.check(Data()) == .failure(.malformed))
        #expect(YouTubeMessage.check(Data("[1]".utf8)) == .failure(.malformed))
        #expect(rejection(["type": "clear"]) == .malformed)
        #expect(rejection(["v": "1", "type": "clear"]) == .malformed)
        #expect(rejection(["v": 1, "type": 3]) == .malformed)
    }

    @Test func anotherVersionOrAnotherTypeIsNamedAsSuch() {
        #expect(rejection(["v": 2, "type": "clear", "videoId": "abcdefghijk"]) == .unsupportedVersion)
        #expect(rejection(["v": 1, "type": "seek"]) == .unknownType)
    }

    @Test func aKnownTypeWithBadFieldsNamesTheType() {
        #expect(rejection(YouTubeMessageTests.captions(videoID: "x")) == .invalidCaptions)
        #expect(rejection(YouTubeMessageTests.playback(rate: 0)) == .invalidPlayback)
        #expect(rejection(["v": 1, "type": "clear", "videoId": "short"]) == .invalidClear)
        #expect(rejection(["v": 1, "type": "diag", "where": "sw", "event": "nonsense"]) == .invalidDiag)
    }

    @Test func theCodesAreFixedWords() {
        let codes = [
            YouTubeMessage.Rejection.malformed, .unsupportedVersion, .unknownType, .invalidCaptions, .invalidPlayback, .invalidClear, .invalidDiag,
        ].map(\.rawValue)
        #expect(codes == ["malformed", "unsupported-version", "unknown-type", "invalid-captions", "invalid-playback", "invalid-clear", "invalid-diag"])
    }

    @Test func theTypeNamesAreTheProtocolsWords() {
        #expect(YouTubeMessage.clear(videoID: "abcdefghijk").typeName == "clear")
        #expect(YouTubeMessage.decode(YouTubeMessageTests.data(YouTubeMessageTests.playback()))?.typeName == "playback")
        #expect(YouTubeMessage.decode(YouTubeMessageTests.data(YouTubeMessageTests.captions()))?.typeName == "captions")
    }
}
