import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import MediaModule

/// The EQ row of the Nhạc tab: it is there only while the Âm thanh module runs, it switches the shared profile and the switch,
/// and it takes a row of the tab without changing the height the tab asks for.
@Suite struct EQQuickControlTests {
    static let width = MediaTabLayoutTests.narrowestContentWidth
    static let available = MediaTabView.preferredHeight - NotchTokens.padding - MediaTabLayoutTests.tabBarHeight
    /// The player alone: nothing above it.
    static let playerAlone = MediaTabView.artworkSize + MediaTabView.lyricGap + CurrentLyricView.height

    /// The suite is emptied when it is released, so the test holds it.
    let defaults = makeIsolatedDefaults()
    let state: EqualizerState

    init() {
        state = EqualizerState(settings: SettingsStore(defaults: defaults))
    }

    func chip(_ name: String, shown: Bool = false) -> MediaSourceChip {
        MediaSourceChip(
            id: .app(name), title: name, detail: "detail", isPlaying: shown, isPrimary: false, isPinned: false, isShown: shown,
            iconBundleID: nil
        )
    }

    /// What the tab asks for with `chipCount` sources, the lyric row there or not, and `equalizer` as the module hands it over.
    func idealHeight(chipCount: Int, equalizer: EqualizerState?, lyricsOn: Bool) -> CGFloat {
        let store = NowPlayingStore(lookUpApp: { _ in nil })
        store.apply(line: AdapterLines.track(), receivedAt: Date())
        store.setLyricsOn(lyricsOn)
        let model = MediaSourceModel()
        model.update(chips: (0..<chipCount).map { chip("app\($0)", shown: $0 == 0) }, displayedID: .app("app0"), primaryID: .app("app0"))
        let tab = MediaTabView(
            store: store, actions: MediaActions(send: { _ in }, seek: { _ in }),
            volume: VolumeModel(hardware: NoVolumeHardware(), queue: ManualVolumeQueue()), sources: model, equalizer: equalizer
        )
        .frame(width: Self.width)
        return NSHostingView(rootView: tab).fittingSize.height
    }

    // MARK: when it is there

    @Test func hiddenWithoutEqualizer() {
        #expect(!EQQuickControl.isShown(nil))
        #expect(NSHostingView(rootView: EQQuickControl(equalizer: nil)).fittingSize == .zero)
        #expect(idealHeight(chipCount: 0, equalizer: nil, lyricsOn: true) == Self.playerAlone)
        #expect(idealHeight(chipCount: 0, equalizer: nil, lyricsOn: false) == MediaTabView.artworkSize)
    }

    @Test func hiddenWhenUnavailable() {
        #expect(!state.isAvailable)
        #expect(!EQQuickControl.isShown(state))
        #expect(NSHostingView(rootView: EQQuickControl(equalizer: state)).fittingSize == .zero)
        #expect(idealHeight(chipCount: 0, equalizer: state, lyricsOn: true) == Self.playerAlone)

        state.isAvailable = true
        #expect(EQQuickControl.isShown(state))
        #expect(NSHostingView(rootView: EQQuickControl(equalizer: state)).fittingSize.height == MediaSourceChipsView.height)

        state.isAvailable = false
        #expect(!EQQuickControl.isShown(state), "the module stopped: the row goes with it")
    }

    // MARK: what it does

    @Test func menuListsTheProfilesAndMarksTheSelectedOne() {
        let control = EQQuickControl(equalizer: state)
        #expect(control.menuItems.map(\.name) == ["Nhạc", "Phim", "Họp"])
        #expect(control.menuItems.map(\.isSelected) == [true, false, false])
        #expect(control.menuItems.map(\.id) == state.profiles.map(\.id))
        #expect(control.title == "Nhạc")
    }

    @Test func menuSelectionSelectsProfile() throws {
        let control = EQQuickControl(equalizer: state)
        let meeting = try #require(control.menuItems.last)
        control.select(meeting.id)
        #expect(state.selectedID == meeting.id)
        #expect(state.selected?.name == "Họp")
        #expect(control.menuItems.map(\.isSelected) == [false, false, true])
        #expect(control.title == "Họp")
    }

    @Test func menuOffersNothingWhenEveryProfileWasDeleted() {
        for profile in state.profiles { state.delete(profile.id) }
        let control = EQQuickControl(equalizer: state)
        #expect(control.menuItems.isEmpty)
        #expect(control.title == EQQuickControl.flatTitle)
        #expect(EQQuickControl.flatTitle == "Phẳng")
    }

    @Test func toggleFlipsEnabled() {
        let control = EQQuickControl(equalizer: state)
        #expect(!control.isOn.wrappedValue)
        control.isOn.wrappedValue = true
        #expect(state.isEnabled)
        #expect(state.activeProfile?.name == "Nhạc", "the same switch the Âm thanh tab has")
        control.isOn.wrappedValue.toggle()
        #expect(!state.isEnabled)
        #expect(state.activeProfile == nil)
    }

    @Test func theSwitchFollowsTheOneOfTheOtherTab() {
        let control = EQQuickControl(equalizer: state)
        state.isEnabled = true
        #expect(control.isOn.wrappedValue)
        state.isEnabled = false
        #expect(!control.isOn.wrappedValue)
    }

    @Test func editCallsOpenEditor() {
        var opened = 0
        state.openEditor = { opened += 1 }
        let control = EQQuickControl(equalizer: state)
        control.edit()
        #expect(opened == 1)
        control.edit()
        #expect(opened == 2)
        #expect(EQQuickControl.editTitle == "Chỉnh…")
    }

    @Test func editWithNoEditorDoesNothing() {
        #expect(state.openEditor == nil)
        EQQuickControl(equalizer: state).edit()
        EQQuickControl(equalizer: nil).edit()
    }

    // MARK: the row in the tab

    @Test func rowWithoutChipsUsesCompactCover() {
        state.isAvailable = true
        let withEQ = idealHeight(chipCount: 0, equalizer: state, lyricsOn: true)
        // The row, the small cover and the lyric row are all of the room, as when the chips are up.
        #expect(withEQ <= Self.available, "\(withEQ) of \(Self.available)")
        #expect(withEQ >= Self.available - 1, "not by leaving the lyric row out: \(withEQ)")
        #expect(withEQ == idealHeight(chipCount: 2, equalizer: nil, lyricsOn: true))
        #expect(MediaTabView.compactArtworkSize < MediaTabView.artworkSize)
    }

    @Test func rowWithoutChipsAndWithoutLyricsKeepsTheFullCover() {
        state.isAvailable = true
        let height = idealHeight(chipCount: 0, equalizer: state, lyricsOn: false)
        #expect(height == MediaSourceChipsView.height + MediaTabView.chipGap + MediaTabView.artworkSize)
        #expect(height <= Self.available)
    }

    @Test func chipsAndTheEQControlShareTheRowAndTheTabKeepsItsHeight() {
        state.isAvailable = true
        for count in [2, 3, 8] {
            for lyricsOn in [true, false] {
                let height = idealHeight(chipCount: count, equalizer: state, lyricsOn: lyricsOn)
                #expect(height <= Self.available, "\(count) sources, lyrics \(lyricsOn): \(height) of \(Self.available)")
                #expect(height == idealHeight(chipCount: count, equalizer: nil, lyricsOn: lyricsOn), "\(count) sources: the row was there already")
            }
        }
    }

    @Test func aLongProfileNameStaysInTheRowsOneLineAndTakesNoMoreThanItsShare() throws {
        state.isAvailable = true
        let short = NSHostingView(rootView: EQQuickControl(equalizer: state)).fittingSize
        let name = String(repeating: "Họp dài ", count: 5).trimmingCharacters(in: .whitespaces)
        #expect(state.rename(try #require(state.selectedID), to: name))
        let long = NSHostingView(rootView: EQQuickControl(equalizer: state)).fittingSize
        #expect(long.height == MediaSourceChipsView.height)
        #expect(long.width - short.width <= EQQuickControl.maxTitleWidth, "the name is cut, not the row grown: \(short.width) then \(long.width)")
        #expect(long.width < Self.width)
        #expect(idealHeight(chipCount: 4, equalizer: state, lyricsOn: true) <= Self.available)
    }

    /// The compact line drops the app's badge because the chips name the app; with no chips the badge stays, and the line still fits.
    @Test func theBadgeLineOfARowWithOnlyTheEQControlFitsTheRoom() {
        state.isAvailable = true
        let app = PlayerApp(name: "Spotify", icon: NSImage(size: NSSize(width: 16, height: 16)))
        func height(chipCount: Int, equalizer: EqualizerState?) -> CGFloat {
            let store = NowPlayingStore(lookUpApp: { _ in app })
            store.apply(line: AdapterLines.track(String(repeating: "A long title ", count: 20)), receivedAt: Date())
            store.setLyricsOn(true)
            #expect(store.appName == "Spotify")
            let model = MediaSourceModel()
            model.update(chips: (0..<chipCount).map { chip("app\($0)", shown: $0 == 0) }, displayedID: .app("app0"), primaryID: .app("app0"))
            let tab = MediaTabView(
                store: store, actions: MediaActions(send: { _ in }, seek: { _ in }),
                volume: VolumeModel(hardware: NoVolumeHardware(), queue: ManualVolumeQueue()), sources: model, equalizer: equalizer
            )
            .frame(width: Self.width)
            return NSHostingView(rootView: tab).fittingSize.height
        }
        #expect(height(chipCount: 0, equalizer: state) <= Self.available)
        #expect(height(chipCount: 3, equalizer: state) <= Self.available)
        #expect(height(chipCount: 0, equalizer: nil) == Self.playerAlone)
    }

    @Test func preferredHeightUnchanged() {
        #expect(MediaTabView.preferredHeight == 160)
        #expect(Self.available == 116)
    }

    // MARK: through the module

    @Test func theModuleHandsItsEqualizerToTheTabAndTheTabKeepsItsHeight() async throws {
        let module = MediaModule(
            source: FakeNowPlayingSource(), spectrum: FakeSpectrumSource(), lyricsClient: FakeHTTPClient(), tokens: FakeTokenStore(),
            signIn: FakeAppleMusicSignIn(), lookUpApp: { _ in nil }, equalizer: state
        )
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()
        module.store.apply(line: AdapterLines.track(), receivedAt: Date())
        module.store.setLyricsOn(false)
        let tab = try #require(harness.registry.tabs.first)
        #expect(tab.preferredHeight == 160)
        func height() -> CGFloat {
            NSHostingView(rootView: tab.content.frame(width: Self.width)).fittingSize.height
        }
        #expect(height() == MediaTabView.artworkSize, "the Âm thanh module is not running: no row")
        state.isAvailable = true
        #expect(height() == MediaSourceChipsView.height + MediaTabView.chipGap + MediaTabView.artworkSize)
        #expect(harness.oversizedTabs.reports.isEmpty)
    }

    @Test func aModuleWithoutAnEqualizerHasTheTabItAlwaysHad() async throws {
        let module = MediaModule(adapterScript: nil, adapterFramework: nil)
        #expect(module.equalizer == nil)
        let withNil = MediaModule(adapterScript: nil, adapterFramework: nil, equalizer: nil)
        #expect(withNil.equalizer == nil)
        let withState = MediaModule(adapterScript: nil, adapterFramework: nil, equalizer: state)
        #expect(withState.equalizer === state)
    }
}
