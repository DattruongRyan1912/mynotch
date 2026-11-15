import AppKit
import NotchUI
import Observation
import SwiftUI
import Testing
@testable import MediaModule

@Suite struct MediaSourceModelTests {
    func chip(_ name: String, playing: Bool = false) -> MediaSourceChip {
        MediaSourceChip(
            id: .app(name), title: name, detail: "", isPlaying: playing, isPrimary: false, isPinned: false, isShown: false, iconBundleID: nil
        )
    }

    @Test func chipsAreForChoosingSoTheyNeedTwoSources() {
        let model = MediaSourceModel()
        #expect(!model.showsChips)
        model.update(chips: [chip("a")], displayedID: .app("a"), primaryID: .app("a"))
        #expect(!model.showsChips)
        model.update(chips: [chip("a"), chip("b")], displayedID: .app("a"), primaryID: .app("a"))
        #expect(model.showsChips)
        #expect(MediaSourceModel.minimumChips == 2)
    }

    @Test func thePlayerShowsThePrimaryUnlessAnotherSourceIsChosen() {
        let model = MediaSourceModel()
        model.update(chips: [chip("a"), chip("b")], displayedID: .app("a"), primaryID: .app("a"))
        #expect(model.displayIsPrimary)
        model.update(chips: [chip("a"), chip("b")], displayedID: .app("b"), primaryID: .app("a"))
        #expect(!model.displayIsPrimary)
    }

    @Test func theViewsAreToldOnlyWhatChanged() async {
        let model = MediaSourceModel()
        let chips = [chip("a"), chip("b")]
        model.update(chips: chips, displayedID: .app("a"), primaryID: .app("a"))
        let changes = Counter()
        func observe() {
            withObservationTracking {
                _ = model.chips
                _ = model.displayedID
                _ = model.primaryID
                _ = model.deniedApps
            } onChange: {
                changes.count += 1
            }
        }
        observe()
        model.update(chips: chips, displayedID: .app("a"), primaryID: .app("a"))
        model.setDeniedApps([])
        #expect(changes.count == 0, "the same values again redraw nothing")
        model.update(chips: chips, displayedID: .app("b"), primaryID: .app("a"))
        #expect(changes.count == 1)
    }

    @Test func theTabIsToldVisibleOrHiddenOnlyOnAChange() {
        let model = MediaSourceModel()
        var told: [Bool] = []
        model.onVisibilityChange = { told.append($0) }
        model.setTabVisible(false)
        model.setTabVisible(true)
        model.setTabVisible(true)
        model.setTabVisible(false)
        model.setTabVisible(false)
        #expect(told == [true, false])
        #expect(!model.isTabVisible)
    }

    @Test func aTapAndAPinGoToWhoeverListens() {
        let model = MediaSourceModel()
        var selected: [MediaSourceID] = []
        var pinned: [MediaSourceID] = []
        model.onSelect = { selected.append($0) }
        model.onTogglePin = { pinned.append($0) }
        model.select(.app("a"))
        model.togglePin(.app("b"))
        #expect(selected == [.app("a")] && pinned == [.app("b")])
    }

    @Test func resettingForgetsEverythingIncludingBeingOnScreen() {
        let model = MediaSourceModel()
        model.update(chips: [chip("a"), chip("b")], displayedID: .app("b"), primaryID: .app("a"))
        model.setDeniedApps(["Music"])
        model.setTabVisible(true)
        model.reset()
        #expect(model.chips.isEmpty && model.displayedID == nil && model.primaryID == nil && model.deniedApps.isEmpty && !model.isTabVisible)
    }
}

private nonisolated final class Counter: @unchecked Sendable {
    nonisolated(unsafe) var count = 0
}

/// The row and the tab with it: it fits the tab's height whatever the player has to show, and the one-source tab is what it was.
@Suite struct MediaSourceChipsLayoutTests {
    static let width = MediaTabLayoutTests.narrowestContentWidth
    static let available = MediaTabView.preferredHeight - NotchTokens.padding - MediaTabLayoutTests.tabBarHeight

    func chip(_ name: String, shown: Bool = false, playing: Bool = false, pinned: Bool = false, title: String? = nil) -> MediaSourceChip {
        MediaSourceChip(
            id: .app(name), title: title ?? name, detail: "detail", isPlaying: playing, isPrimary: false, isPinned: pinned, isShown: shown,
            iconBundleID: nil
        )
    }

    /// What the tab asks for with `sourceCount` sources, the lyric row there or not, the player showing the primary source or another.
    func idealHeight(
        sourceCount: Int, lyricsOn: Bool, showsPrimary: Bool = true, unsynced: Bool = false, hidden: Bool = false,
        layout: MediaControlLayout = .standard, longTitles: Bool = false
    ) -> CGFloat {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        let display = NowPlayingStore(lookUpApp: { _ in nil })
        let line = AdapterLines.track(longTitles ? String(repeating: "A long title ", count: 20) : "Song")
        store.apply(line: line, receivedAt: Date())
        display.apply(line: line, receivedAt: Date())
        for shown in [store, display] {
            shown.setLyricsOn(lyricsOn)
            shown.setControlLayout(layout)
        }
        if unsynced { store.showUnsyncedLyrics() }
        if hidden { store.toggleLyricsHidden() }
        let model = MediaSourceModel()
        let chips = (0..<sourceCount).map { chip("app\($0)", shown: $0 == 0, playing: $0 == 0) }
        model.update(chips: chips, displayedID: .app(showsPrimary ? "app0" : "app1"), primaryID: .app("app0"))
        let tab = MediaTabView(
            store: store, actions: MediaActions(send: { _ in }, seek: { _ in }),
            volume: VolumeModel(hardware: NoVolumeHardware(), queue: ManualVolumeQueue()), sources: model, displayStore: display
        )
        .frame(width: Self.width)
        return NSHostingView(rootView: tab).fittingSize.height
    }

    @Test func withOneSourceTheTabIsExactlyWhatItAlwaysWas() {
        #expect(idealHeight(sourceCount: 1, lyricsOn: false) == MediaTabView.artworkSize)
        #expect(idealHeight(sourceCount: 1, lyricsOn: true) == MediaTabView.artworkSize + MediaTabView.lyricGap + CurrentLyricView.height)
        #expect(idealHeight(sourceCount: 0, lyricsOn: true) == MediaTabView.artworkSize + MediaTabView.lyricGap + CurrentLyricView.height)
    }

    @Test func theDeclaredHeightIsThatOfTheOneSourceTab() {
        #expect(MediaTabView.preferredHeight == 160)
        #expect(Self.available == 116)
    }

    @Test func theChipsAndThePlayerFitTheTabsHeightWithoutALyricRow() {
        for count in [2, 3, 8] {
            let height = idealHeight(sourceCount: count, lyricsOn: false)
            #expect(height <= Self.available, "\(count) sources: \(height) of \(Self.available)")
            #expect(height >= MediaSourceChipsView.height + MediaTabView.chipGap + MediaTabView.artworkSize - 1, "the chips are in it")
        }
    }

    @Test func theChipsAndThePlayerAndItsLyricRowFitTheTabsHeightTooWhateverThePlayerShows() {
        for count in [2, 3, 8] {
            for showsPrimary in [true, false] {
                for (unsynced, hidden) in [(false, false), (true, false), (false, true)] {
                    let height = idealHeight(sourceCount: count, lyricsOn: true, showsPrimary: showsPrimary, unsynced: unsynced, hidden: hidden)
                    #expect(height <= Self.available, "\(count) sources, primary \(showsPrimary), unsynced \(unsynced), hidden \(hidden): \(height) of \(Self.available)")
                    // Not by leaving the lyric row out: the row, the chips and the player together are all of the room.
                    #expect(height >= Self.available - 1, "\(count) sources, primary \(showsPrimary): \(height)")
                }
            }
        }
    }

    @Test func aLongTitleAndFiveButtonsStayInTheRoomToo() {
        let all = MediaControlLayout(slots: [.shuffle, .previous, .next, .repeatMode])
        #expect(idealHeight(sourceCount: 4, lyricsOn: true, layout: all, longTitles: true) <= Self.available)
        #expect(idealHeight(sourceCount: 4, lyricsOn: false, layout: all, longTitles: true) <= Self.available)
    }

    @Test func theRowIsOneLineHighWhateverThereIsInIt() {
        for count in [2, 5, 30] {
            let model = MediaSourceModel()
            model.update(chips: (0..<count).map { chip("app\($0)", title: "A track number \($0)") }, displayedID: nil, primaryID: nil)
            let row = MediaSourceChipsView(model: model, icons: PlayerAppCache(lookUp: { _ in nil })).frame(width: Self.width)
            let size = NSHostingView(rootView: row).fittingSize
            #expect(size.height == MediaSourceChipsView.height, "\(count) chips")
            #expect(size.width <= Self.width, "the row scrolls instead of growing (\(count) chips)")
        }
    }

    @Test func theMenuOffersToPinAndToUnpin() {
        #expect(MediaSourceChipsView.pinTitle == "Luôn hiện nguồn này")
        #expect(MediaSourceChipsView.unpinTitle == "Bỏ ghim nguồn này")
    }

    @Test func theChipsStateIsSaidInWordsForVoiceOver() {
        // The chip's state is said in words.
        let playing = MediaSourceChipsView.state(of: chip("a", playing: true))
        #expect(playing == "đang phát")
        #expect(MediaSourceChipsView.state(of: chip("a", pinned: true)) == "tạm dừng, đã ghim")
    }
}

/// The tab tells its sources when it is on screen, which is what makes Apple Events worth sending.
@Suite struct MediaTabVisibilityTests {
    func host(model: MediaSourceModel) -> (NSWindow, NSHostingView<MediaTabView>) {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(), receivedAt: Date())
        let view = MediaTabView(
            store: store, actions: MediaActions(send: { _ in }, seek: { _ in }),
            volume: VolumeModel(hardware: NoVolumeHardware(), queue: ManualVolumeQueue()), sources: model
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(x: 0, y: 0, width: MediaSourceChipsLayoutTests.width, height: 200)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return (window, hosting)
    }

    @Test func theTabIsVisibleWhileItIsInAWindowAndNotAfterItLeaves() async {
        let model = MediaSourceModel()
        let (window, _) = host(model: model)
        for _ in 0..<50 where !model.isTabVisible { await Task.yield() }
        #expect(model.isTabVisible)
        window.contentView = NSView()
        for _ in 0..<50 where model.isTabVisible { await Task.yield() }
        #expect(!model.isTabVisible)
    }
}
