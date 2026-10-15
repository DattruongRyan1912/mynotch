import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import MediaModule

/// The tint and the spectrum colours through the module: settings in, the store's colours out, with a fake source and a
/// counting stand-in for the background extraction.
@Suite final class MediaTintTests {
    let source = FakeNowPlayingSource()
    let extractor = FakeExtractor()
    let module: MediaModule
    let harness: RegistryHarness
    let storageBase: URL

    /// What the fake extraction answers for a cover, by its bytes.
    let redCover = SyntheticImage.png(SyntheticImage.solid(SRGBColor(red: 1, green: 0, blue: 0), size: 8))
    let greenCover = SyntheticImage.png(SyntheticImage.solid(SRGBColor(red: 0, green: 1, blue: 0), size: 8))
    let red = ArtworkPalette(primary: SRGBColor(red: 1, green: 0, blue: 0), secondary: nil)
    let green = ArtworkPalette(primary: SRGBColor(red: 0, green: 1, blue: 0), secondary: nil)

    init() {
        let extractor = extractor
        module = MediaModule(
            source: source, spectrum: FakeSpectrumSource(), lyricsClient: FakeHTTPClient(), tokens: FakeTokenStore(),
            signIn: FakeAppleMusicSignIn(), lookUpApp: { _ in nil }, tintExtract: { await extractor.extract($0) }
        )
        harness = RegistryHarness([module])
        storageBase = harness.storageRoot.caches.deletingLastPathComponent()
        extractor.answer(red, for: redCover)
        extractor.answer(green, for: greenCover)
    }

    deinit { try? FileManager.default.removeItem(at: storageBase) }

    var keys: MediaSettingsKeys { MediaSettingsKeys(harness.settingsEnvironment(for: "media")!.settings) }
    var store: NowPlayingStore { module.store }

    func play(_ title: String = "Song", cover: Data? = nil) {
        source.emit(AdapterLines.track(title, artworkBase64: cover?.base64EncodedString()))
    }

    // MARK: settings

    @Test func theTintAndTheCoverModeAreOnByDefault() async {
        #expect(keys.tintFromArtwork.defaultValue == true)
        #expect(keys.spectrumColorMode.defaultValue == .artwork)
        #expect(keys.spectrumGradientStart.defaultValue == SpectrumColorMode.defaultStart)
        #expect(keys.spectrumGradientEnd.defaultValue == SpectrumColorMode.defaultEnd)
        await harness.registry.bootstrap()
        #expect(store.tintEnabled)
        #expect(store.spectrumMode == .artwork)
    }

    @Test func theChoicesAreKeptInTheSettings() {
        let start = SRGBColor(red: 0.1, green: 0.2, blue: 0.3)
        harness.settings.set(false, for: keys.tintFromArtwork)
        harness.settings.set(SpectrumColorMode.gradient, for: keys.spectrumColorMode)
        harness.settings.set(start, for: keys.spectrumGradientStart)
        #expect(harness.settings.value(keys.tintFromArtwork) == false)
        #expect(harness.settings.value(keys.spectrumColorMode) == .gradient)
        #expect(harness.settings.value(keys.spectrumGradientStart) == start)
        harness.settings.reset(keys.spectrumColorMode)
        #expect(harness.settings.value(keys.spectrumColorMode) == .artwork)
    }

    @Test func choicesMadeBeforeTheModuleStartsAreUsedFromTheStart() async {
        let end = SRGBColor(red: 0.9, green: 0.8, blue: 0.1)
        harness.settings.set(false, for: keys.tintFromArtwork)
        harness.settings.set(SpectrumColorMode.gradient, for: keys.spectrumColorMode)
        harness.settings.set(end, for: keys.spectrumGradientEnd)
        await harness.registry.bootstrap()
        #expect(!store.tintEnabled)
        #expect(store.spectrumMode == .gradient)
        #expect(store.spectrumGradientEnd == end)
        #expect(store.spectrumColors?.last == end)
    }

    @Test func aChangeOfTheChoicesReachesTheStoreWhileTheModuleRuns() async {
        await harness.registry.bootstrap()
        harness.settings.set(SpectrumColorMode.white, for: keys.spectrumColorMode)
        #expect(await waitUntil { store.spectrumMode == .white })
        let start = SRGBColor(red: 1, green: 0, blue: 0)
        harness.settings.set(SpectrumColorMode.gradient, for: keys.spectrumColorMode)
        harness.settings.set(start, for: keys.spectrumGradientStart)
        #expect(await waitUntil { store.spectrumMode == .gradient && store.spectrumGradientStart == start })
        harness.settings.set(false, for: keys.tintFromArtwork)
        #expect(await waitUntil { !store.tintEnabled })
    }

    // MARK: the tint of a track

    @Test func aTrackWithACoverGetsItsTint() async {
        await harness.registry.bootstrap()
        play(cover: redCover)
        #expect(await waitUntil { store.tint == red })
        #expect(store.activeTint == red)
        #expect(store.spectrumColors?.first == red.primary)
    }

    @Test func theTintIsWorkedOutOncePerTrackWhateverTheStateDoesMeanwhile() async {
        await harness.registry.bootstrap()
        play(cover: redCover)
        #expect(await waitUntil { store.tint == red })
        source.emit(AdapterLines.position(40))
        source.emit(AdapterLines.playing(false))
        source.emit(AdapterLines.playing(true))
        source.emit(AdapterLines.position(50))
        #expect(extractor.callCount == 1)

        play("Another", cover: greenCover)
        #expect(await waitUntil { store.tint == green })
        #expect(extractor.callCount == 2)
    }

    @Test func aTrackPlayedAgainIsTintedFromTheCache() async {
        await harness.registry.bootstrap()
        play("First", cover: redCover)
        #expect(await waitUntil { store.tint == red })
        play("Second", cover: greenCover)
        #expect(await waitUntil { store.tint == green })
        play("First", cover: redCover)
        #expect(store.tint == red, "at once")
        #expect(extractor.callCount == 2)
    }

    @Test func aTrackWithoutACoverHasNoTint() async {
        await harness.registry.bootstrap()
        play(cover: redCover)
        #expect(await waitUntil { store.tint == red })
        play("Radio")
        #expect(store.tint == nil)
        #expect(store.spectrumColors == nil)
    }

    @Test func theTintStaysThroughTheEmptyStateBetweenTwoTracks() async {
        await harness.registry.bootstrap()
        play(cover: redCover)
        #expect(await waitUntil { store.tint == red })
        source.emit(AdapterLines.empty)
        #expect(store.tint == red, "the player does not flash between two tracks")
    }

    // MARK: the setting

    @Test func withTheSettingOffNothingIsWorkedOutAndNothingIsTinted() async {
        harness.settings.set(false, for: keys.tintFromArtwork)
        await harness.registry.bootstrap()
        play(cover: redCover)
        for _ in 0..<50 { await Task.yield() }
        #expect(extractor.callCount == 0)
        #expect(store.tint == nil)
        #expect(store.activeTint == nil)
    }

    @Test func switchingTheSettingOnTintsWhatIsPlayingAndOffTakesItAway() async {
        harness.settings.set(false, for: keys.tintFromArtwork)
        await harness.registry.bootstrap()
        play(cover: redCover)
        harness.settings.set(true, for: keys.tintFromArtwork)
        #expect(await waitUntil { store.activeTint == red })
        harness.settings.set(false, for: keys.tintFromArtwork)
        #expect(await waitUntil { store.activeTint == nil })
        harness.settings.set(true, for: keys.tintFromArtwork)
        #expect(await waitUntil { store.activeTint == red })
        #expect(extractor.callCount == 1, "the second time it came from the cache")
    }

    @Test func theCoverModeOfTheBarsFollowsTheSetting() async {
        await harness.registry.bootstrap()
        play(cover: redCover)
        #expect(await waitUntil { store.spectrumColors != nil })
        harness.settings.set(false, for: keys.tintFromArtwork)
        #expect(await waitUntil { store.spectrumColors == nil })
    }

    @Test func stoppingTheModuleForgetsTheTintAndStartingAgainFindsItAgain() async {
        await harness.registry.bootstrap()
        play(cover: redCover)
        #expect(await waitUntil { store.tint == red })
        await harness.registry.setEnabled(false, for: "media")
        #expect(store.tint == nil)
        await harness.registry.setEnabled(true, for: "media")
        play(cover: redCover)
        #expect(store.tint == red, "the cache is the module's, which outlives a stop")
    }
}
