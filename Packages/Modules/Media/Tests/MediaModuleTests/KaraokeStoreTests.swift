import Foundation
import Observation
import Testing
@testable import MediaModule

@Suite struct KaraokeStoreTests {
    nonisolated final class Flag: @unchecked Sendable {
        nonisolated(unsafe) var isSet = false
    }

    let words = [LyricLine(time: 1, words: [LyricWord(text: "la ", begin: 1, end: 2), LyricWord(text: "la", begin: 2, end: 3)])]
    let plain = [LyricLine(time: 1, text: "la la")]

    func makeStore() -> NowPlayingStore { NowPlayingStore(lookUpApp: { _ in nil }) }

    @Test func karaokeIsOnByDefaultAndNeedsWordTimingToBeActive() {
        let store = makeStore()
        #expect(store.karaokeEnabled)
        #expect(!store.karaokeIsActive)
        store.showLyrics(plain)
        #expect(!store.lyricsHaveWordTiming)
        #expect(!store.karaokeIsActive)
        store.showLyrics(words)
        #expect(store.lyricsHaveWordTiming)
        #expect(store.karaokeIsActive)
    }

    @Test func oneTimedLineAmongPlainOnesIsEnough() {
        let store = makeStore()
        store.showLyrics(plain + words)
        #expect(store.lyricsHaveWordTiming)
    }

    @Test func turningTheSettingOffStopsItWithoutLosingTheTiming() {
        let store = makeStore()
        store.showLyrics(words)
        store.setKaraokeEnabled(false)
        #expect(!store.karaokeIsActive)
        #expect(store.lyricsHaveWordTiming)
        store.setKaraokeEnabled(true)
        #expect(store.karaokeIsActive)
    }

    @Test func lyricsThatGoTakeTheTimingWithThem() {
        let store = makeStore()
        store.showLyrics(words)
        store.showLyrics(nil)
        #expect(!store.lyricsHaveWordTiming)
        store.showLyrics(words)
        store.showUnsyncedLyrics()
        #expect(!store.lyricsHaveWordTiming)
        store.showLyrics(words)
        store.reset()
        #expect(!store.karaokeIsActive)
    }

    @Test func aViewHearsOfEveryChangeOfWhetherItIsActive() {
        let store = makeStore()
        let invalidated = Flag()
        withObservationTracking { _ = store.karaokeIsActive } onChange: { invalidated.isSet = true }
        store.showLyrics(words)
        #expect(invalidated.isSet)
        invalidated.isSet = false
        withObservationTracking { _ = store.karaokeIsActive } onChange: { invalidated.isSet = true }
        store.setKaraokeEnabled(false)
        #expect(invalidated.isSet)
    }

    @Test func settingTheSameValueAgainChangesNothing() {
        let store = makeStore()
        let invalidated = Flag()
        withObservationTracking { _ = store.karaokeEnabled; _ = store.lyricsPanelShown; _ = store.lyricsHaveWordTiming } onChange: { invalidated.isSet = true }
        store.setKaraokeEnabled(true)
        store.setLyricsPanelShown(false)
        store.showLyrics(plain)
        store.showLyrics(plain)
        #expect(!invalidated.isSet)
    }

    @Test func thePanelStateIsTheModulesToSet() {
        let store = makeStore()
        #expect(!store.lyricsPanelShown)
        store.setLyricsPanelShown(true)
        #expect(store.lyricsPanelShown)
    }

    @Test func thePanelLinesFollowThePlaybackClock() {
        let store = makeStore()
        store.setLyricsOn(true)
        store.showLyrics([LyricLine(time: 5, text: "a"), LyricLine(time: 10, text: "b"), LyricLine(time: 15, text: "c")])
        store.apply(line: AdapterLines.track(elapsed: 11), receivedAt: Date())
        let shown = store.lyricPanel(at: Date())
        #expect(shown?.previous?.text == "a")
        #expect(shown?.current?.text == "b")
        #expect(shown?.next?.text == "c")
        store.showLyrics(nil)
        #expect(store.lyricPanel(at: Date()) == nil)
    }
}
