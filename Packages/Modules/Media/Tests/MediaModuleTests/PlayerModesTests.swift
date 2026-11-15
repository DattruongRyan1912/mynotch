import Foundation
import Testing
@testable import MediaModule

/// The shuffle and repeat modes, the like and skip flags: how they cycle and how the adapter's payload becomes them.
@Suite struct PlayerModesTests {
    func applying(_ lines: String...) -> NowPlayingReducer {
        var reducer = NowPlayingReducer()
        for line in lines { #expect(reducer.apply(line: line, receivedAt: Date(timeIntervalSince1970: 1_760_000_000)) == .applied) }
        return reducer
    }

    func line(diff: Bool = false, _ payload: String) -> String {
        #"{"type":"data","diff":\#(diff),"payload":\#(payload)}"#
    }

    // MARK: cycling

    @Test func repeatCyclesFromOffThroughAllToOneAndBackToOff() {
        #expect(RepeatMode.off.next == .playlist)
        #expect(RepeatMode.playlist.next == .track)
        #expect(RepeatMode.track.next == .off)
    }

    @Test func shuffleComesOnForTracksAndAnyOnModeGoesOff() {
        #expect(ShuffleMode.off.toggled == .tracks)
        #expect(ShuffleMode.tracks.toggled == .off)
        #expect(ShuffleMode.albums.toggled == .off)
        #expect(!ShuffleMode.off.isOn)
        #expect(ShuffleMode.albums.isOn && ShuffleMode.tracks.isOn)
    }

    @Test func theAdaptersIdsAreTheModesAndAnythingElseCountsAsOff() {
        #expect(ShuffleMode.allCases.map(\.rawValue) == [1, 2, 3], "`shuffle MODE` takes these ids (README)")
        #expect(RepeatMode.allCases.map(\.rawValue) == [1, 2, 3], "`repeat MODE` takes these ids (README)")
        #expect([1.0, 2, 3].map(ShuffleMode.init(reported:)) == [.off, .albums, .tracks])
        #expect([1.0, 2, 3].map(RepeatMode.init(reported:)) == [.off, .track, .playlist])
        for odd in [0.0, 4, -1, 2.5, .nan, .infinity] {
            #expect(ShuffleMode(reported: odd) == .off, "\(odd)")
            #expect(RepeatMode(reported: odd) == .off, "\(odd)")
        }
    }

    // MARK: the payload

    @Test func aPlayerThatReportsNoneOfThemHasNoModesAndNoFlags() {
        let state = applying(line(#"{"bundleIdentifier":"com.example.Player","title":"Song","playing":true}"#)).state
        #expect(state.shuffleMode == nil)
        #expect(state.repeatMode == nil)
        #expect(!state.isLiked)
        #expect(!state.supportsIsLiked)
        #expect(!state.prohibitsSkip)
    }

    @Test func modesAndFlagsAreReadFromThePayload() {
        let state = applying(line(#"{"bundleIdentifier":"com.example.Player","title":"Song","shuffleMode":3,"repeatMode":2,"isLiked":true,"supportsIsLiked":true,"prohibitsSkip":true}"#)).state
        #expect(state.shuffleMode == .tracks)
        #expect(state.repeatMode == .track)
        #expect(state.isLiked)
        #expect(state.supportsIsLiked)
        #expect(state.prohibitsSkip)
    }

    @Test func aFlagMayComeAsANumber() {
        let on = applying(line(#"{"bundleIdentifier":"a","title":"Song","isLiked":1,"supportsIsLiked":1,"prohibitsSkip":1}"#)).state
        #expect(on.isLiked && on.supportsIsLiked && on.prohibitsSkip)
        let off = applying(line(#"{"bundleIdentifier":"a","title":"Song","isLiked":0,"supportsIsLiked":0,"prohibitsSkip":0}"#)).state
        #expect(!off.isLiked && !off.supportsIsLiked && !off.prohibitsSkip)
    }

    @Test func aDiffChangesOneModeAndNullTakesItAway() {
        let full = line(#"{"bundleIdentifier":"a","title":"Song","shuffleMode":1,"repeatMode":1,"isLiked":false}"#)
        let changed = applying(full, line(diff: true, #"{"repeatMode":3,"isLiked":true}"#)).state
        #expect(changed.repeatMode == .playlist)
        #expect(changed.shuffleMode == .off)
        #expect(changed.isLiked)
        let gone = applying(full, line(diff: true, #"{"shuffleMode":null,"isLiked":null}"#)).state
        #expect(gone.shuffleMode == nil)
        #expect(gone.repeatMode == .off)
        #expect(!gone.isLiked)
    }

    @Test func theModesDoNotChangeWhichTrackItIs() {
        let first = applying(line(#"{"bundleIdentifier":"a","title":"Song","shuffleMode":1}"#)).state
        let second = applying(line(#"{"bundleIdentifier":"a","title":"Song","shuffleMode":3,"isLiked":true}"#)).state
        #expect(first.trackIdentity == second.trackIdentity, "the activity is published once per track")
    }
}
