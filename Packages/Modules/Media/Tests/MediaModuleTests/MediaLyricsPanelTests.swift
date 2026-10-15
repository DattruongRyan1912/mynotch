import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import MediaModule

/// The module's side of the floating lyrics panel and karaoke: the settings, the hotkey, the Media tab's button and the window's
/// life. No panel is ever put on a screen: `presentLyricsPanel` records it.
@Suite final class MediaLyricsPanelTests {
    let source = FakeNowPlayingSource()
    let client = FakeHTTPClient()
    let module: MediaModule
    let harness: RegistryHarness
    let storageBase: URL
    let presented = Presented()
    static let display = PanelDisplay(
        key: "MAIN", frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805)
    )

    final class Presented {
        var panels: [NSPanel] = []
    }

    init() {
        module = MediaModule(
            source: source, spectrum: FakeSpectrumSource(), lyricsClient: client, tokens: FakeTokenStore(),
            signIn: FakeAppleMusicSignIn(), lookUpApp: { _ in nil }
        )
        let presented = presented
        module.presentLyricsPanel = { presented.panels.append($0) }
        module.lyricsPanelDisplays = { [Self.display] }
        harness = RegistryHarness([module])
        storageBase = harness.storageRoot.caches.deletingLastPathComponent()
    }

    deinit { try? FileManager.default.removeItem(at: storageBase) }

    var keys: MediaSettingsKeys { MediaSettingsKeys(harness.settingsEnvironment(for: "media")!.settings) }
    var store: NowPlayingStore { module.store }

    func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    func start() async { await harness.registry.bootstrap() }

    // MARK: settings

    @Test func theSettingsHaveTheirDefaultsAndNames() {
        #expect(keys.karaoke.defaultValue == true)
        #expect(keys.lyricsPanel.defaultValue == false)
        #expect(keys.lyricsPanelFontSize.defaultValue == LyricsPanelModel.defaultFontSize)
        #expect(keys.lyricsPanelOpacity.defaultValue == 0.9)
        #expect(keys.lyricsPanelClickThrough.defaultValue == false)
        #expect(keys.lyricsPanelFrames.defaultValue == LyricsPanelPlacement())
        #expect(keys.karaoke.name == "module.media.karaoke")
        #expect(keys.lyricsPanel.name == "module.media.lyricsPanel")
        #expect(keys.lyricsPanelFontSize.name == "module.media.lyricsPanelFontSize")
        #expect(keys.lyricsPanelOpacity.name == "module.media.lyricsPanelOpacity")
        #expect(keys.lyricsPanelClickThrough.name == "module.media.lyricsPanelClickThrough")
        #expect(keys.lyricsPanelFrames.name == "module.media.lyricsPanelFrames")
    }

    @Test func theSizeAndTheOpacityAreKeptWithinWhatWorks() {
        harness.settings.set(3.0, for: keys.lyricsPanelFontSize)
        #expect(harness.settings.value(keys.lyricsPanelFontSize) == LyricsPanelModel.fontSizeRange.lowerBound)
        harness.settings.set(900.0, for: keys.lyricsPanelFontSize)
        #expect(harness.settings.value(keys.lyricsPanelFontSize) == LyricsPanelModel.fontSizeRange.upperBound)
        harness.settings.set(0.0, for: keys.lyricsPanelOpacity)
        #expect(harness.settings.value(keys.lyricsPanelOpacity) == LyricsPanelController.opacityRange.lowerBound)
        harness.settings.set(4.0, for: keys.lyricsPanelOpacity)
        #expect(harness.settings.value(keys.lyricsPanelOpacity) == 1)
    }

    @Test func theRowsSayWhatTheyDo() {
        #expect(MediaSettingsView.karaokeTitle == "Tô theo từng chữ")
        #expect(LyricsPanelRows.title == "Bảng lời nổi")
        #expect(LyricsPanelRows.fontSizeTitle == "Cỡ chữ của bảng")
        #expect(LyricsPanelRows.opacityTitle == "Độ mờ của bảng")
        #expect(LyricsPanelRows.clickThroughTitle == "Cho chuột xuyên qua bảng")
    }

    @Test func theSettingsPageGetsTheRows() async {
        await start()
        let environment = harness.settingsEnvironment(for: "media")!
        #expect(module.makeSettingsView(environment) != nil)
    }

    // MARK: karaoke

    @Test func theKaraokeSettingReachesTheStoreAtStartAndWhenItChanges() async {
        harness.settings.set(false, for: keys.karaoke)
        await start()
        #expect(!store.karaokeEnabled)
        harness.settings.set(true, for: keys.karaoke)
        await settle { store.karaokeEnabled }
        #expect(store.karaokeEnabled)
    }

    // MARK: the panel

    @Test func theSettingShowsAndHidesThePanel() async {
        await start()
        #expect(module.lyricsPanelController?.isShown == false)
        #expect(!store.lyricsPanelShown)
        harness.settings.set(true, for: keys.lyricsPanel)
        await settle { module.lyricsPanelController?.isShown == true }
        #expect(module.lyricsPanelController?.isShown == true)
        #expect(store.lyricsPanelShown)
        #expect(presented.panels.count == 1)
        harness.settings.set(false, for: keys.lyricsPanel)
        await settle { module.lyricsPanelController?.isShown == false }
        #expect(module.lyricsPanelController?.isShown == false)
        #expect(!store.lyricsPanelShown)
    }

    @Test func aPanelLeftOnComesBackWithTheApp() async {
        harness.settings.set(true, for: keys.lyricsPanel)
        await start()
        #expect(module.lyricsPanelController?.isShown == true)
        #expect(store.lyricsPanelShown)
    }

    @Test func theHotkeyHasNoKeyByDefaultAndTogglesThePanel() async {
        await start()
        let registration = harness.hotkeys.registrations.first { $0.name.rawValue == "media_lyricsPanel" }
        #expect(registration?.title == "Bật/tắt bảng lời nổi")
        #expect(harness.hotkeyBackend.getShortcut(for: registration!.name) == nil)
        #expect(harness.hotkeyBackend.trigger("media_lyricsPanel"))
        #expect(harness.settings.value(keys.lyricsPanel))
        #expect(module.lyricsPanelController?.isShown == true)
        #expect(harness.hotkeyBackend.trigger("media_lyricsPanel"))
        #expect(!harness.settings.value(keys.lyricsPanel))
        #expect(module.lyricsPanelController?.isShown == false)
    }

    @Test func theMediaTabsButtonDoesTheSame() async {
        await start()
        module.actions.toggleLyricsPanel()
        #expect(harness.settings.value(keys.lyricsPanel))
        #expect(store.lyricsPanelShown)
        module.actions.toggleLyricsPanel()
        #expect(!harness.settings.value(keys.lyricsPanel))
        #expect(!store.lyricsPanelShown)
    }

    @Test func sizeOpacityAndClickThroughReachThePanelWhileItIsUp() async throws {
        harness.settings.set(true, for: keys.lyricsPanel)
        await start()
        let panel = try #require(module.lyricsPanelController?.panel)
        harness.settings.set(0.5, for: keys.lyricsPanelOpacity)
        harness.settings.set(true, for: keys.lyricsPanelClickThrough)
        harness.settings.set(30.0, for: keys.lyricsPanelFontSize)
        await settle { panel.ignoresMouseEvents && module.lyricsPanelModel?.fontSize == 30 && abs(panel.alphaValue - 0.5) < 1e-6 }
        #expect(abs(panel.alphaValue - 0.5) < 1e-6)
        #expect(panel.ignoresMouseEvents)
        #expect(module.lyricsPanelModel?.fontSize == 30)
    }

    @Test func changingASettingOfThePanelDoesNotBringItForwardAgain() async {
        harness.settings.set(true, for: keys.lyricsPanel)
        await start()
        let before = presented.panels.count
        harness.settings.set(0.5, for: keys.lyricsPanelOpacity)
        await settle { module.lyricsPanelController?.panel?.alphaValue != 1 }
        #expect(presented.panels.count == before)
    }

    @Test func whereTheUserLeavesThePanelIsKeptInTheSettingsAndComesBack() async throws {
        harness.settings.set(true, for: keys.lyricsPanel)
        await start()
        let controller = try #require(module.lyricsPanelController)
        let panel = try #require(controller.panel)
        panel.setFrame(CGRect(x: 260, y: 340, width: 520, height: 160), display: false)
        controller.frameChanged()
        harness.scheduler.advance(by: .seconds(1))
        let stored = harness.settings.value(keys.lyricsPanelFrames)
        #expect(stored.restoredFrame(among: [Self.display]) == CGRect(x: 260, y: 340, width: 520, height: 160))
        harness.settings.set(false, for: keys.lyricsPanel)
        await settle { !controller.isShown }
        harness.settings.set(true, for: keys.lyricsPanel)
        await settle { controller.isShown }
        #expect(controller.panel?.frame == CGRect(x: 260, y: 340, width: 520, height: 160))
    }

    @Test func stoppingTheModuleClosesThePanelAndLeavesTheSettingAlone() async throws {
        harness.settings.set(true, for: keys.lyricsPanel)
        await start()
        let panel = try #require(module.lyricsPanelController?.panel)
        await module.stop()
        #expect(module.lyricsPanelController == nil)
        #expect(!panel.isVisible)
        #expect(!store.lyricsPanelShown)
        #expect(harness.settings.value(keys.lyricsPanel))
    }
}

@Suite struct LyricsPanelToggleTests {
    @Test func theButtonSaysWhetherThePanelIsUp() {
        let off = LyricsPanelToggle.look(isShown: false)
        let on = LyricsPanelToggle.look(isShown: true)
        #expect(off.symbol != on.symbol)
        #expect(off.label == "Bảng lời nổi: tắt")
        #expect(on.label == "Bảng lời nổi: bật")
        #expect(on.isActive && !off.isActive)
    }
}
