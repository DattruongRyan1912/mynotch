import Foundation
import Testing
@testable import MediaModule

@Suite struct NowPlayingReducerTests {
    /// Hand-written in the adapter's `stream --micros` format (README sections `get` and `stream`).
    static let fullLine = #"""
    {"type":"data","diff":false,"payload":{"bundleIdentifier":"com.example.Player.helper","parentApplicationBundleIdentifier":"com.example.Player","playing":true,"title":"First Song","artist":"Some Artist","album":"Some Album","durationMicros":200000000,"elapsedTimeMicros":30500000,"timestampEpochMicros":1760000000000000,"playbackRate":1,"artworkMimeType":"image/png","artworkData":"AQID","uniqueIdentifier":42,"contentItemIdentifier":"item-1","isAdvertisement":false,"genre":"Pop","queueIndex":3}}
    """#

    static let anchorDate = Date(timeIntervalSince1970: 1_760_000_000)

    func line(diff: Bool, _ payload: String) -> String {
        #"{"type":"data","diff":\#(diff),"payload":\#(payload)}"#
    }

    func applying(_ lines: String...) -> NowPlayingReducer {
        var reducer = NowPlayingReducer()
        for line in lines { #expect(reducer.apply(line: line) == .applied) }
        return reducer
    }

    @Test func fullPayloadReplacesState() {
        let expected = NowPlayingState(
            bundleIdentifier: "com.example.Player.helper",
            parentApplicationBundleIdentifier: "com.example.Player",
            title: "First Song", artist: "Some Artist", album: "Some Album",
            durationSeconds: 200,
            elapsedAnchor: PlaybackAnchor(elapsedSeconds: 30.5, timestamp: Self.anchorDate, rate: 1),
            isPlaying: true,
            artwork: ArtworkData(data: Data([1, 2, 3]), mimeType: "image/png", revision: 1),
            uniqueIdentifier: "42", contentItemIdentifier: "item-1",
            isAdvertisement: false
        )
        #expect(applying(Self.fullLine).state == expected)
        #expect(expected.isActive)

        let replaced = applying(Self.fullLine, line(diff: false, #"{"bundleIdentifier":"com.other.App","playing":false,"title":"Other"}"#))
        #expect(replaced.state == NowPlayingState(bundleIdentifier: "com.other.App", title: "Other"))
    }

    @Test func diffOverwritesPresentKeysAndKeepsAbsentOnes() {
        let reducer = applying(Self.fullLine, line(diff: true, #"{"title":"Second Song","artist":"New Artist"}"#))
        #expect(reducer.state.title == "Second Song")
        #expect(reducer.state.artist == "New Artist")
        #expect(reducer.state.album == "Some Album")
        #expect(reducer.state.durationSeconds == 200)
        #expect(reducer.state.isPlaying)
        #expect(reducer.state.artwork?.revision == 1)
    }

    @Test func nullRemovesKeysInDiff() {
        let reducer = applying(Self.fullLine, line(diff: true, #"{"artist":null,"durationMicros":null,"playing":null,"isAdvertisement":null,"artworkData":null,"uniqueIdentifier":null}"#))
        #expect(reducer.state.artist == nil)
        #expect(reducer.state.durationSeconds == nil)
        #expect(!reducer.state.isPlaying)
        #expect(reducer.state.artwork == nil)
        #expect(reducer.state.uniqueIdentifier == nil)
        #expect(reducer.state.title == "First Song")
    }

    @Test func emptyOrNullPayloadMeansNothingPlays() {
        #expect(applying(Self.fullLine, line(diff: false, "{}")).state == .empty)
        #expect(applying(Self.fullLine, line(diff: true, "{}")).state == .empty)
        #expect(applying(Self.fullLine, line(diff: false, "null")).state == .empty)
        #expect(!NowPlayingState.empty.isActive)
        #expect(!NowPlayingState(bundleIdentifier: "com.example.Player").isActive)
    }

    @Test func malformedLinesAreIgnored() {
        var reducer = applying(Self.fullLine)
        let before = reducer.state
        for bad in ["", "not json", #"{"type":"data","diff":true"#, #"{"type":"data","diff":false,"payload":"oops"}"#, #"{"diff":false,"payload":{}}"#, "[1,2]"] {
            #expect(reducer.apply(line: bad) == .ignored)
        }
        #expect(reducer.state == before)
    }

    @Test func nonDataLinesAreIgnored() {
        var reducer = applying(Self.fullLine)
        let before = reducer.state
        #expect(reducer.apply(line: #"{"type":"error","diff":false,"payload":{}}"#) == .ignored)
        #expect(reducer.state == before)
    }

    @Test func artworkRevisionChangesOnlyWithItsBytes() {
        var reducer = applying(Self.fullLine)
        #expect(reducer.state.artwork == ArtworkData(data: Data([1, 2, 3]), mimeType: "image/png", revision: 1))

        reducer.apply(line: line(diff: true, #"{"artworkData":"AQID","elapsedTimeMicros":31000000}"#))
        reducer.apply(line: Self.fullLine)
        #expect(reducer.state.artwork?.revision == 1)

        reducer.apply(line: line(diff: true, #"{"artworkData":"BAUG","artworkMimeType":"image/jpeg"}"#))
        #expect(reducer.state.artwork == ArtworkData(data: Data([4, 5, 6]), mimeType: "image/jpeg", revision: 2))

        reducer.apply(line: line(diff: true, #"{"artworkData":null}"#))
        #expect(reducer.state.artwork == nil)

        reducer.apply(line: line(diff: true, #"{"artworkData":"AQID"}"#))
        #expect(reducer.state.artwork?.revision == 3)
    }

    @Test func artworkSurvivesUpdatesWithoutItForTheSameTrack() {
        let diffed = applying(Self.fullLine, line(diff: true, #"{"elapsedTimeMicros":40000000,"playing":false}"#))
        #expect(diffed.state.artwork?.revision == 1)

        let sameTrack = Self.fullLine.replacingOccurrences(of: #""artworkData":"AQID","#, with: "")
        #expect(applying(Self.fullLine, sameTrack).state.artwork == ArtworkData(data: Data([1, 2, 3]), mimeType: "image/png", revision: 1))

        let otherTrack = sameTrack.replacingOccurrences(of: "First Song", with: "Second Song")
        #expect(applying(Self.fullLine, otherTrack).state.artwork == nil)
    }

    @Test func convertsMicrosecondsToSeconds() {
        let reducer = applying(line(diff: false, #"{"bundleIdentifier":"com.example.Player","playing":true,"title":"T","durationMicros":2500000,"elapsedTimeMicros":1500000,"timestampEpochMicros":1760000000250000}"#))
        #expect(reducer.state.durationSeconds == 2.5)
        #expect(reducer.state.elapsedAnchor == PlaybackAnchor(elapsedSeconds: 1.5, timestamp: Date(timeIntervalSince1970: 1_760_000_000.25), rate: 1))

        let noLength = applying(Self.fullLine, line(diff: true, #"{"durationMicros":0}"#))
        #expect(noLength.state.durationSeconds == nil)
    }

    @Test func pausedOrZeroRateGivesAPausedAnchor() {
        var reducer = applying(Self.fullLine, line(diff: true, #"{"playing":false}"#))
        #expect(reducer.state.elapsedAnchor?.rate == 0)
        #expect(!reducer.state.isPlaying)

        reducer.apply(line: line(diff: true, #"{"playing":true,"playbackRate":2}"#))
        #expect(reducer.state.elapsedAnchor?.rate == 2)

        reducer.apply(line: line(diff: true, #"{"playbackRate":0}"#))
        #expect(reducer.state.elapsedAnchor?.rate == 0)
    }
}
