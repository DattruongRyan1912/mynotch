import AppKit
import MyNotchCore
import NotchUI
import SwiftUI
import Testing
@testable import MediaModule

@Suite struct LyricRowTests {
    let lines = [LyricLine(time: 1, text: "a")]

    func makeStore() -> NowPlayingStore {
        NowPlayingStore(lookUpApp: { _ in nil })
    }

    @Test func isAbsentWhileNoLyricsSourceIsOn() {
        let store = makeStore()
        #expect(store.lyricRow == .absent)
    }

    @Test func keepsItsPlaceWhileASourceIsOnAndThereIsNothingToShowYet() {
        let store = makeStore()
        store.setLyricsOn(true)
        #expect(store.lyricRow == .reserved)
        // Still fetching, nothing found, a track without a key: the row stays, so the player never moves.
        store.reset()
        #expect(store.lyricRow == .reserved)
        store.setLyricsOn(false)
        #expect(store.lyricRow == .absent)
    }

    @Test func showsTheLinesOrTheUnsyncedNoteInTheSamePlace() {
        let store = makeStore()
        store.setLyricsOn(true)
        store.showLyrics(lines)
        #expect(store.lyricRow == .synced)
        store.showUnsyncedLyrics()
        #expect(store.lyricRow == .unsynced)
        store.showLyrics(nil)
        #expect(store.lyricRow == .reserved)
    }

    @Test func lyricsStillThereAreShownEvenAfterTheSourceTurnedOff() {
        // They are dropped by the module a moment later; the row follows what the store holds.
        let store = makeStore()
        store.setLyricsOn(true)
        store.showLyrics(lines)
        store.setLyricsOn(false)
        #expect(store.lyricRow == .synced)
        store.showLyrics(nil)
        #expect(store.lyricRow == .absent)
    }
}

@Suite struct MediaTabLayoutTests {
    /// The narrowest content width a notch gives its tab: 480pt wide, less the 8pt corner ears and 14pt padding each side.
    static let narrowestContentWidth: CGFloat = 480 - 2 * (8 + NotchTokens.padding)
    /// What the tab bar takes when there are two or more tabs (the usual case); `NotchTab.preferredHeight` includes it.
    static let tabBarHeight: CGFloat = 30

    func idealHeight(lyricsOn: Bool, unsynced: Bool = false, hidden: Bool = false, layout: MediaControlLayout = .standard) throws -> CGFloat {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(), receivedAt: Date())
        store.setLyricsOn(lyricsOn)
        store.setControlLayout(layout)
        if unsynced { store.showUnsyncedLyrics() }
        if hidden { store.toggleLyricsHidden() }
        let tab = MediaTabView(store: store, actions: MediaActions(send: { _ in }, seek: { _ in }), volume: VolumeModel(device: NoVolumeDevice()))
            .frame(width: Self.narrowestContentWidth)
        return NSHostingView(rootView: tab).fittingSize.height
    }

    @Test func declaredHeightHoldsThePlayerThenItsLyricRowPlusTheNotchChrome() {
        let content = MediaTabView.artworkSize + MediaTabView.lyricGap + CurrentLyricView.height
        #expect(MediaTabView.preferredHeight == content + NotchTokens.padding + Self.tabBarHeight)
        #expect(NotchTab.heightRange.contains(MediaTabView.preferredHeight))
    }

    @Test func playerWithItsLyricRowFitsTheDeclaredHeight() throws {
        let available = MediaTabView.preferredHeight - NotchTokens.padding - Self.tabBarHeight
        #expect(try idealHeight(lyricsOn: true) <= available)
        #expect(try idealHeight(lyricsOn: true, unsynced: true) <= available)
    }

    @Test func theLyricRowAddsItsHeightAndGapBelowTheControlsAndNothingElseMoves() throws {
        let without = try idealHeight(lyricsOn: false)
        let with = try idealHeight(lyricsOn: true)
        #expect(without == MediaTabView.artworkSize)
        #expect(with - without == MediaTabView.lyricGap + CurrentLyricView.height)
        #expect(try idealHeight(lyricsOn: true, unsynced: true) == with)
    }

    @Test func hidingTheLyricsKeepsTheRowsPlaceSoThePlayerStaysWhereItIs() throws {
        #expect(try idealHeight(lyricsOn: true, hidden: true) == idealHeight(lyricsOn: true))
        #expect(try idealHeight(lyricsOn: true, unsynced: true, hidden: true) == idealHeight(lyricsOn: true))
    }

    @Test func fiveButtonsLeaveTheTabsHeightAndTheLayoutWhereItWas() throws {
        let all = MediaControlLayout(slots: [.shuffle, .previous, .next, .repeatMode])
        #expect(try idealHeight(lyricsOn: true, layout: all) == idealHeight(lyricsOn: true))
        #expect(try idealHeight(lyricsOn: false, layout: all) == MediaTabView.artworkSize)
    }

    @Test func theRowOfFiveButtonsFitsBesideTheCoverInTheNarrowestNotchWithRoomForTheBars() {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(), receivedAt: Date())
        store.setControlLayout(MediaControlLayout(slots: [.shuffle, .previous, .next, .repeatMode]))
        let row = MediaControlsRow(store: store, actions: MediaActions(send: { _ in }, seek: { _ in }), volume: VolumeModel(device: NoVolumeDevice()))
        let width = NSHostingView(rootView: row).fittingSize.width
        let columnWidth = Self.narrowestContentWidth - MediaTabView.artworkSize - 14
        #expect(width > 0)
        #expect(width <= columnWidth - 2 * 40, "\(width) of \(columnWidth)")
    }
}
