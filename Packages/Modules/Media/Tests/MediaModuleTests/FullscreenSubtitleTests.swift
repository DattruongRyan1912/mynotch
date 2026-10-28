import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import MediaModule

/// A system the overlay looks at: windows, displays and apps the test sets, and a handle on the events it listens for.
@MainActor
final class FakeOverlaySystem {
    static let main = SubtitleOverlayDisplay(
        id: 1, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982), frame: CGRect(x: 0, y: 0, width: 1512, height: 982)
    )
    static let external = SubtitleOverlayDisplay(
        id: 2, bounds: CGRect(x: 1512, y: 0, width: 1920, height: 1080), frame: CGRect(x: 1512, y: -98, width: 1920, height: 1080)
    )
    static let chrome: pid_t = 42
    static let xcode: pid_t = 7

    /// Each process's fullscreen windows, as Accessibility gives them.
    var fullscreenWindows: [pid_t: [CGRect]] = [:]
    var displays = [main, external]
    var apps = ["com.google.Chrome": chrome, "com.apple.dt.Xcode": xcode]
    /// The player's window as the screen has it, fullscreen or not.
    var playerWindow: CGRect?
    private(set) var handler: (@MainActor () -> Void)?
    private(set) var listening = false

    var environment: FullscreenSubtitleOverlay.Environment {
        FullscreenSubtitleOverlay.Environment(
            fullscreenWindows: { [unowned self] pids in pids.flatMap { fullscreenWindows[$0] ?? [] } },
            displays: { [unowned self] in displays },
            playerWindow: { [unowned self] _ in playerWindow },
            processes: { [unowned self] ids in Set(ids.compactMap { apps[$0] }) },
            observe: { [unowned self] handler in
                self.handler = handler
                listening = true
                return { [unowned self] in listening = false }
            }
        )
    }

    /// The app's window fullscreen on `display`, starting a point below the camera housing as Chrome's does.
    func fullscreen(_ pid: pid_t, on display: SubtitleOverlayDisplay) {
        let bounds = display.bounds
        fullscreenWindows = [pid: [CGRect(x: bounds.minX, y: bounds.minY + 39, width: bounds.width, height: bounds.height - 39)]]
    }

    func windowed(_ pid: pid_t) {
        fullscreenWindows = [:]
    }

    /// A Space change, an app to the front: what the overlay listens for.
    func somethingChanged() { handler?() }
}

@Suite struct FullscreenSubtitleRuleTests {
    let displays = [FakeOverlaySystem.main, FakeOverlaySystem.external]

    @Test func theDisplayHoldingAFullscreenWindowGetsTheSubtitles() {
        let onExternal = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
        #expect(FullscreenSubtitleRule.display(fullscreenWindows: [onExternal], displays: displays) == FakeOverlaySystem.external)
        // Below the camera housing, a point lower than macOS's own fullscreen windows, as Chrome's is.
        let belowTheHousing = CGRect(x: 0, y: 39, width: 1512, height: 943)
        #expect(FullscreenSubtitleRule.display(fullscreenWindows: [belowTheHousing], displays: displays) == FakeOverlaySystem.main)
    }

    @Test func noFullscreenWindowOrOneOffEveryDisplayHasNone() {
        #expect(FullscreenSubtitleRule.display(fullscreenWindows: [], displays: displays) == nil)
        let nowhere = CGRect(x: -3000, y: 0, width: 800, height: 600)
        #expect(FullscreenSubtitleRule.display(fullscreenWindows: [nowhere], displays: displays) == nil)
    }

    @Test func theLinesSitAtTheBottomCentredAndSizedByTheScreen() {
        let screen = FakeOverlaySystem.external.frame
        let frame = FullscreenSubtitleRule.frame(on: screen)
        // 1920 × 1080 below the main display: 80% of the width, 7% up from its bottom, text 4.5% of its height.
        #expect(frame == CGRect(x: 1704, y: -23, width: 1536, height: 157))
        #expect(abs(FullscreenSubtitleRule.fontSize(screenHeight: 1080) - 48.6) < 0.001)
        #expect(FullscreenSubtitleRule.fontSize(screenHeight: 300) == 22)
    }
}

@MainActor
@Suite final class FullscreenSubtitleOverlayTests {
    let system = FakeOverlaySystem()
    let scheduler = ManualScheduler()
    let store = NowPlayingStore()
    var presented: [NSPanel] = []
    var changes = 0
    lazy var overlay: FullscreenSubtitleOverlay = {
        let overlay = FullscreenSubtitleOverlay(store: store, scheduler: scheduler, environment: system.environment) { [unowned self] in
            presented.append($0)
        }
        overlay.onChange = { [unowned self] in changes += 1 }
        return overlay
    }()

    @Test func offItNeitherLooksNorShows() {
        system.fullscreen(FakeOverlaySystem.chrome, on: FakeOverlaySystem.main)
        overlay.update(enabled: false, playerBundleIDs: ["com.google.Chrome"])
        #expect(!overlay.isShown)
        #expect(!system.listening)
        #expect(presented.isEmpty)
    }

    @Test func turnedOnWhileTheFilmIsFullscreenItShowsAtOnce() throws {
        system.fullscreen(FakeOverlaySystem.chrome, on: FakeOverlaySystem.external)
        overlay.update(enabled: true, playerBundleIDs: ["com.google.Chrome"])
        #expect(overlay.display == FakeOverlaySystem.external)
        #expect(changes == 1)
        let panel = try #require(presented.last)
        #expect(panel.frame == FullscreenSubtitleRule.frame(on: FakeOverlaySystem.external.frame))
        // The pointer goes through where nothing is drawn: no background, and the window takes presses only on the letters.
        #expect(panel.backgroundColor == .clear)
        #expect(!panel.isOpaque)
        #expect(!panel.canBecomeKey)
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    @Test func goingFullscreenAndBackIsSeenAfterTheSpaceSettles() {
        system.windowed(FakeOverlaySystem.chrome)
        overlay.update(enabled: true, playerBundleIDs: ["com.google.Chrome"])
        #expect(!overlay.isShown)
        #expect(system.listening)

        // The Space is still sliding when the event comes: the window fills the screen a moment later.
        system.somethingChanged()
        #expect(!overlay.isShown)
        system.fullscreen(FakeOverlaySystem.chrome, on: FakeOverlaySystem.main)
        scheduler.advance(by: .milliseconds(500))
        #expect(overlay.display == FakeOverlaySystem.main)

        system.windowed(FakeOverlaySystem.chrome)
        system.somethingChanged()
        #expect(!overlay.isShown)
        #expect(presented.last?.isVisible == false)
        #expect(changes == 2)
    }

    @Test func anotherAppFullscreenLeavesItOff() {
        system.fullscreen(FakeOverlaySystem.xcode, on: FakeOverlaySystem.main)
        overlay.update(enabled: true, playerBundleIDs: ["com.google.Chrome"])
        system.somethingChanged()
        scheduler.advance(by: .seconds(2))
        #expect(!overlay.isShown)
        #expect(changes == 0)
    }

    @Test func turningOffTakesItAwayAndStopsListening() {
        system.fullscreen(FakeOverlaySystem.chrome, on: FakeOverlaySystem.main)
        overlay.update(enabled: true, playerBundleIDs: ["com.google.Chrome"])
        system.somethingChanged()
        overlay.close()
        #expect(!overlay.isShown)
        #expect(!system.listening)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func theSameInputsLookOnce() {
        system.fullscreen(FakeOverlaySystem.chrome, on: FakeOverlaySystem.main)
        overlay.update(enabled: true, playerBundleIDs: ["com.google.Chrome"])
        overlay.update(enabled: true, playerBundleIDs: ["com.google.Chrome"])
        #expect(presented.count == 1)
        #expect(changes == 1)
    }
}

@MainActor
@Suite final class MediaFullscreenSubtitleTests {
    let source = FakeNowPlayingSource()
    let system = FakeOverlaySystem()
    let module: MediaModule
    let harness: RegistryHarness
    let storageBase: URL
    let files = ScratchFolders.shared.reserveShort()

    init() {
        module = MediaModule(
            source: source, spectrum: FakeSpectrumSource(), lyricsClient: FakeHTTPClient(), tokens: FakeTokenStore(),
            signIn: FakeAppleMusicSignIn(), lookUpApp: { _ in nil }
        )
        module.subtitleOverlayEnvironment = system.environment
        module.presentSubtitleOverlay = { _ in }
        harness = RegistryHarness([module])
        storageBase = harness.storageRoot.caches.deletingLastPathComponent()
    }

    deinit {
        try? FileManager.default.removeItem(at: storageBase)
        try? FileManager.default.removeItem(at: files)
    }

    var keys: MediaSettingsKeys { MediaSettingsKeys(harness.settingsEnvironment(for: "media")!.settings) }
    var store: NowPlayingStore { module.store }
    var activity: LiveActivity? { harness.activities.current?.activity }

    func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    /// The strip on, a film playing in Chrome with its subtitles loaded.
    func playFilmWithSubtitles() async throws {
        harness.settings.set(true, for: keys.lyricsUnderNotch)
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track(MediaSubtitleTests.film, artist: "", bundle: "com.google.Chrome", elapsed: 60, duration: 6_000))
        await settle { store.state.isActive }
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let url = files.appending(path: "intern.srt")
        try Data(MediaSubtitleTests.srt.utf8).write(to: url)
        #expect(module.loadSubtitles(from: url))
        await settle { activity?.hasBottom == true }
    }

    @Test func theSettingIsOffByDefaultAndSaysWhatItDoes() {
        #expect(keys.fullscreenSubtitles.defaultValue == false)
        #expect(keys.fullscreenSubtitles.name == "module.media.fullscreenSubtitles")
        #expect(MediaSettingsView.fullscreenSubtitlesTitle == "Phụ đề trên phim khi xem toàn màn hình")
    }

    @Test func withTheSettingOffAFullscreenFilmKeepsTheStrip() async throws {
        system.fullscreen(FakeOverlaySystem.chrome, on: FakeOverlaySystem.main)
        try await playFilmWithSubtitles()
        #expect(module.subtitleOverlay?.isShown == false)
        #expect(activity?.hasBottom == true)
    }

    @Test func aFullscreenFilmHasItsSubtitlesOverItAndNotUnderTheNotch() async throws {
        system.windowed(FakeOverlaySystem.chrome)
        try await playFilmWithSubtitles()
        harness.settings.set(true, for: keys.fullscreenSubtitles)
        await settle { system.listening }
        #expect(module.subtitleOverlay?.isShown == false)
        #expect(activity?.hasBottom == true)

        system.fullscreen(FakeOverlaySystem.chrome, on: FakeOverlaySystem.main)
        system.somethingChanged()
        #expect(module.subtitleOverlay?.display == FakeOverlaySystem.main)
        #expect(activity?.hasBottom == false)

        system.windowed(FakeOverlaySystem.chrome)
        system.somethingChanged()
        #expect(module.subtitleOverlay?.isShown == false)
        #expect(activity?.hasBottom == true)
    }

    @Test func removingTheSubtitlesTakesThemOffTheFilm() async throws {
        system.fullscreen(FakeOverlaySystem.chrome, on: FakeOverlaySystem.main)
        harness.settings.set(true, for: keys.fullscreenSubtitles)
        try await playFilmWithSubtitles()
        #expect(module.subtitleOverlay?.isShown == true)
        module.removeSubtitles()
        #expect(module.subtitleOverlay?.isShown == false)
        #expect(!system.listening)
    }

    @Test func betweenTwoSubtitlesThereIsNothingOnTheFilm() async throws {
        try await playFilmWithSubtitles()
        // Playing from 60 s: the first line from 71.64 s to 74.53 s, the next from 80 s.
        let anchor = try #require(store.state.elapsedAnchor)
        func at(_ seconds: Double) -> Date { anchor.timestamp.addingTimeInterval(seconds - anchor.elapsedSeconds) }
        #expect(store.subtitle(at: at(65)) == "")
        #expect(store.subtitle(at: at(72)) == "Freud said, \"Love and work.")
        #expect(store.subtitle(at: at(77)) == "")
        #expect(store.subtitle(at: at(80.5)) == "That's all there is.")
    }
}

@MainActor
@Suite final class FullscreenSubtitleHeightTests {
    let system = FakeOverlaySystem()
    let store = NowPlayingStore()
    var presented: [NSPanel] = []

    @Test func theLinesMoveToTheHeightChosenAtOnce() throws {
        let overlay = FullscreenSubtitleOverlay(store: store, scheduler: ManualScheduler(), environment: system.environment) { [unowned self] in
            presented.append($0)
        }
        system.fullscreen(FakeOverlaySystem.chrome, on: FakeOverlaySystem.main)
        overlay.update(enabled: true, playerBundleIDs: ["com.google.Chrome"])
        let panel = try #require(presented.last)
        let screen = FakeOverlaySystem.main.frame
        // 982 pt tall: 7% up is 68.7 pt, whole points down.
        #expect(panel.frame.minY == 68)
        overlay.setBottomGap(0.3)
        #expect(panel.frame.minY == 294)
        #expect(FullscreenSubtitleRule.frame(on: screen, bottomGap: 5).minY == 589, "no higher than 60%")
    }
}

@MainActor
@Suite final class MediaFullscreenSubtitleHeightTests {
    let system = FakeOverlaySystem()
    let module = MediaModule(
        source: FakeNowPlayingSource(), spectrum: FakeSpectrumSource(), lyricsClient: FakeHTTPClient(), tokens: FakeTokenStore(),
        signIn: FakeAppleMusicSignIn(), lookUpApp: { _ in nil }
    )
    lazy var harness = RegistryHarness([module])
    var keys: MediaSettingsKeys { MediaSettingsKeys(harness.settingsEnvironment(for: "media")!.settings) }
    var presented: [FullscreenSubtitlePanel] = []

    @Test func draggingTheLinesRemembersTheirHeightWithinTheRange() async throws {
        module.subtitleOverlayEnvironment = system.environment
        module.presentSubtitleOverlay = { [unowned self] in presented.append($0 as! FullscreenSubtitlePanel) }
        await harness.registry.bootstrap()
        #expect(keys.fullscreenSubtitlesHeight.defaultValue == 0.07)
        system.fullscreen(FakeOverlaySystem.chrome, on: FakeOverlaySystem.main)
        let overlay = try #require(module.subtitleOverlay)
        overlay.update(enabled: true, playerBundleIDs: ["com.google.Chrome"])
        let panel = try #require(presented.last)
        let screen = FakeOverlaySystem.main.frame
        // The band's bottom is kept between 0% and 60% of the screen while dragged.
        #expect(panel.allowedMinY == 0...589)

        panel.onDragged(491)
        #expect(abs(harness.settings.value(keys.fullscreenSubtitlesHeight) - 491 / screen.height) < 1e-9)
        #expect(FullscreenSubtitleRule.bottomGap(forBandAt: 2_000, on: screen) == 0.6)
        #expect(FullscreenSubtitleRule.bottomGap(forBandAt: -50, on: screen) == 0)
    }
}

@MainActor
@Suite final class FloatingSubtitleTests {
    let system = FakeOverlaySystem()
    let store = NowPlayingStore()
    var presented: [FullscreenSubtitlePanel] = []
    var scales: [Double] = []
    lazy var overlay: FullscreenSubtitleOverlay = {
        let overlay = FullscreenSubtitleOverlay(store: store, scheduler: ManualScheduler(), environment: system.environment) { [unowned self] in
            presented.append($0 as! FullscreenSubtitlePanel)
        }
        overlay.onScaleChanged = { [unowned self] in scales.append($0) }
        return overlay
    }()

    @Test func shownByHandTheyAreUpOnThePlayersScreenWithoutFullscreen() {
        system.windowed(FakeOverlaySystem.chrome)
        system.playerWindow = CGRect(x: 1700, y: 100, width: 900, height: 600)
        overlay.update(enabled: false, forced: true, playerBundleIDs: ["com.google.Chrome"])
        #expect(overlay.isForced)
        #expect(overlay.display == FakeOverlaySystem.external)
        overlay.update(enabled: false, forced: false, playerBundleIDs: ["com.google.Chrome"])
        #expect(!overlay.isShown)
    }

    @Test func withoutAWindowFoundTheyGoOnTheFirstScreen() {
        overlay.update(enabled: false, forced: true, playerBundleIDs: ["com.google.Chrome"])
        #expect(overlay.display == FakeOverlaySystem.main)
    }

    @Test func aFullscreenFilmStillHasThemOverIt() {
        system.playerWindow = CGRect(x: 100, y: 100, width: 900, height: 600)
        system.fullscreen(FakeOverlaySystem.chrome, on: FakeOverlaySystem.external)
        overlay.update(enabled: false, forced: true, playerBundleIDs: ["com.google.Chrome"])
        #expect(overlay.display == FakeOverlaySystem.external)
    }

    @Test func pinchingOrScrollingResizesThemWithinTheRangeTheirBottomWhereItWas() throws {
        overlay.update(enabled: false, forced: true, playerBundleIDs: ["com.google.Chrome"])
        let panel = try #require(presented.last)
        let before = panel.frame
        panel.onScaled(1.5)
        #expect(scales == [1.5])
        #expect(panel.frame.minY == before.minY)
        #expect(panel.frame.height > before.height * 1.4)
        panel.onScaled(10)
        #expect(scales.last == FullscreenSubtitleRule.scaleRange.upperBound)
        panel.onScaled(2)
        #expect(scales.count == 2, "no larger than the range: nothing to remember")
        #expect(FullscreenSubtitleRule.fontSize(screenHeight: 1080, scale: 0.1) == FullscreenSubtitleRule.fontSize(screenHeight: 1080) * 0.5)
    }
}

@MainActor
@Suite final class MediaFloatingSubtitleTests {
    let source = FakeNowPlayingSource()
    let system = FakeOverlaySystem()
    let module = MediaModule(
        source: FakeNowPlayingSource(), spectrum: FakeSpectrumSource(), lyricsClient: FakeHTTPClient(), tokens: FakeTokenStore(),
        signIn: FakeAppleMusicSignIn(), lookUpApp: { _ in nil }
    )
    lazy var harness = RegistryHarness([module])
    var keys: MediaSettingsKeys { MediaSettingsKeys(harness.settingsEnvironment(for: "media")!.settings) }

    @Test func theMenuTurnsThemOnAndTheyAreRemembered() async {
        module.subtitleOverlayEnvironment = system.environment
        module.presentSubtitleOverlay = { _ in }
        await harness.registry.bootstrap()
        #expect(keys.floatingSubtitles.defaultValue == false)
        #expect(keys.floatingSubtitlesScale.defaultValue == 1)
        module.setFloatingSubtitles(true)
        #expect(harness.settings.value(keys.floatingSubtitles))
        #expect(module.subtitleControls.floating?() == true)
        // No film with subtitles yet: nothing to float.
        #expect(module.subtitleOverlay?.isShown == false)
    }
}
