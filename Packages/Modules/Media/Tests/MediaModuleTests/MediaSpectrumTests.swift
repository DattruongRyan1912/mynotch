import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import MediaModule

@Suite struct MediaSpectrumTests {
    let source = FakeNowPlayingSource()
    let spectrum = FakeSpectrumSource()
    let module: MediaModule
    let harness: RegistryHarness

    init() {
        module = MediaModule(source: source, spectrum: spectrum, lyricsClient: FakeHTTPClient(), lookUpApp: { _ in nil })
        harness = RegistryHarness([module])
    }

    var keys: MediaSettingsKeys { MediaSettingsKeys(harness.settingsEnvironment(for: "media")!.settings) }
    var store: NowPlayingStore { module.store }

    /// Lets the module's observation loops run after a settings write or a bars view change.
    func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() { await Task.yield() }
    }

    /// For changes with nothing observable to wait for: enough turns for the observation loops to see them.
    func letObservationsRun() async {
        await settle { false }
    }

    /// Real spectrum on, a track playing and bars on screen: everything the tap waits for.
    func startTap() async {
        harness.settings.set(true, for: keys.realSpectrum)
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        store.spectrumViewAppeared()
        await settle { spectrum.isStarted }
        #expect(spectrum.isStarted)
    }

    @Test func offByDefaultNeverStartsTheTap() async {
        #expect(keys.realSpectrum.defaultValue == false)
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        store.spectrumViewAppeared()
        await settle { spectrum.isStarted }
        #expect(spectrum.startCount == 0)
        #expect(store.spectrumBands == nil)
    }

    @Test func startsOnlyWhileSomethingPlays() async {
        harness.settings.set(true, for: keys.realSpectrum)
        await harness.registry.bootstrap()
        store.spectrumViewAppeared()
        await settle { spectrum.isStarted }
        #expect(!spectrum.isStarted)

        source.emit(AdapterLines.track(playing: false))
        #expect(!spectrum.isStarted)
        source.emit(AdapterLines.playing(true))
        #expect(spectrum.isStarted)
        #expect(spectrum.startCount == 1)
    }

    @Test func startsOnlyWhileBarsAreOnScreen() async {
        harness.settings.set(true, for: keys.realSpectrum)
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        await settle { spectrum.isStarted }
        #expect(!spectrum.isStarted)

        store.spectrumViewAppeared()
        await settle { spectrum.isStarted }
        #expect(spectrum.isStarted)
    }

    @Test func barsShowTheTapsBands() async {
        await startTap()
        let bands: [Float] = [0.1, 0.5, 0.9, 0.3]
        spectrum.emit(.bands(bands))
        #expect(store.spectrumBands == bands)
        let levels = NowPlayingBars.levels(spectrum: store.spectrumBands, isPlaying: store.activityIsPlaying, at: .now)
        #expect(levels == bands.map(Double.init))

        source.emit(AdapterLines.playing(false))
        #expect(NowPlayingBars.levels(spectrum: store.spectrumBands, isPlaying: store.activityIsPlaying, at: .now) == [0, 0, 0, 0])
    }

    @Test func barsWithoutBandsKeepTheMadeUpMotion() {
        let date = Date(timeIntervalSinceReferenceDate: 1234.5)
        let made = (0..<NowPlayingBars.barCount).map { NowPlayingBars.level(bar: $0, at: date) }
        #expect(NowPlayingBars.levels(spectrum: nil, isPlaying: true, at: date) == made)
        #expect(NowPlayingBars.levels(spectrum: nil, isPlaying: false, at: date) == [0, 0, 0, 0])
        // Fewer bands than bars leave the rest at rest; out-of-range values are clamped.
        #expect(NowPlayingBars.levels(spectrum: [2, -1], isPlaying: true, at: date) == [1, 0, 0, 0])
    }

    @Test func pausingStopsTheTapAfterADelay() async {
        await startTap()
        spectrum.emit(.bands([0.2, 0.2, 0.2, 0.2]))
        source.emit(AdapterLines.playing(false))
        harness.scheduler.advance(by: .milliseconds(1900))
        #expect(spectrum.isStarted)
        harness.scheduler.advance(by: .milliseconds(100))
        #expect(!spectrum.isStarted)
        #expect(store.spectrumBands == nil)
    }

    @Test func aTrackChangeKeepsTheTapRunning() async {
        await startTap()
        source.emit(AdapterLines.empty)
        harness.scheduler.advance(by: .milliseconds(500))
        source.emit(AdapterLines.track("Next"))
        harness.scheduler.advance(by: .seconds(10))
        #expect(spectrum.isStarted)
        #expect(spectrum.startCount == 1)
        #expect(spectrum.stopCount == 0)
    }

    @Test func hidingTheBarsStopsTheTapAfterADelay() async {
        await startTap()
        store.spectrumViewDisappeared()
        await settle { harness.scheduler.pendingCount > 0 }
        harness.scheduler.advance(by: .milliseconds(1900))
        #expect(spectrum.isStarted)
        harness.scheduler.advance(by: .milliseconds(100))
        #expect(!spectrum.isStarted)
    }

    /// Opening the notch swaps the activity's bars for the tab's; the tap keeps running through the swap.
    @Test func barsMovingBetweenViewsKeepTheTapRunning() async {
        await startTap()
        store.spectrumViewDisappeared()
        await settle { harness.scheduler.pendingCount > 0 }
        store.spectrumViewAppeared()
        await settle { harness.scheduler.pendingCount == 0 }
        harness.scheduler.advance(by: .seconds(10))
        #expect(spectrum.isStarted)
        #expect(spectrum.startCount == 1)
    }

    @Test func turningTheSettingOffStopsTheTapAtOnce() async {
        await startTap()
        spectrum.emit(.bands([0.2, 0.2, 0.2, 0.2]))
        harness.settings.set(false, for: keys.realSpectrum)
        await settle { !spectrum.isStarted }
        #expect(!spectrum.isStarted)
        #expect(store.spectrumBands == nil)
    }

    @Test func likelyDeniedShowsTheHintAndTheMadeUpMotion() async {
        await startTap()
        spectrum.emit(.bands([0, 0, 0, 0]))
        spectrum.emit(.permissionLikelyDenied(true))
        #expect(store.spectrumPermissionLikelyDenied)
        #expect(store.spectrumBands == nil)
        // A denied tap keeps delivering silence; the bars keep the made-up motion meanwhile.
        spectrum.emit(.bands([0, 0, 0, 0]))
        #expect(store.spectrumBands == nil)

        spectrum.emit(.permissionLikelyDenied(false))
        #expect(!store.spectrumPermissionLikelyDenied)
        spectrum.emit(.bands([0.4, 0.4, 0.4, 0.4]))
        #expect(store.spectrumBands == [0.4, 0.4, 0.4, 0.4])
    }

    @Test func turningTheSettingOffClearsTheHint() async {
        await startTap()
        spectrum.emit(.permissionLikelyDenied(true))
        harness.settings.set(false, for: keys.realSpectrum)
        await settle { !store.spectrumPermissionLikelyDenied }
        #expect(!store.spectrumPermissionLikelyDenied)
    }

    @Test func aFailedTapStaysOffUntilTheSettingIsTurnedOnAgain() async {
        await startTap()
        spectrum.emit(.bands([0.3, 0.3, 0.3, 0.3]))
        spectrum.emit(.failed("Could not create the process tap"))
        #expect(!spectrum.isStarted)
        #expect(store.spectrumBands == nil)

        source.emit(AdapterLines.playing(false))
        source.emit(AdapterLines.playing(true))
        store.spectrumViewDisappeared()
        store.spectrumViewAppeared()
        await settle { spectrum.isStarted }
        #expect(spectrum.startCount == 1)

        harness.settings.set(false, for: keys.realSpectrum)
        await letObservationsRun()
        harness.settings.set(true, for: keys.realSpectrum)
        await settle { spectrum.isStarted }
        #expect(spectrum.startCount == 2)
    }

    @Test func stoppingTheModuleStopsTheTap() async {
        await startTap()
        spectrum.emit(.permissionLikelyDenied(true))
        await harness.registry.setEnabled(false, for: "media")
        #expect(!spectrum.isStarted)
        #expect(store.spectrumBands == nil)
        #expect(!store.spectrumPermissionLikelyDenied)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func barsOnScreenNeverCountBelowZero() {
        store.spectrumViewDisappeared()
        #expect(store.spectrumViewCount == 0)
        store.spectrumViewAppeared()
        store.spectrumViewAppeared()
        store.spectrumViewDisappeared()
        #expect(store.spectrumViewCount == 1)
    }

    @Test func permissionHintOpensTheSystemAudioRecordingPane() {
        #expect(MediaSettingsView.audioCaptureSettingsURL.absoluteString
            == "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")
    }
}
