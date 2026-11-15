import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import MediaModule

@Suite struct MediaLockScreenTests {
    let source = FakeNowPlayingSource()
    let module: MediaModule
    let harness: RegistryHarness

    init() {
        module = MediaModule(source: source, spectrum: FakeSpectrumSource(), lyricsClient: FakeHTTPClient(), tokens: FakeTokenStore(), signIn: FakeAppleMusicSignIn(), lookUpApp: { _ in nil })
        harness = RegistryHarness([module])
    }

    var keys: MediaSettingsKeys { MediaSettingsKeys(harness.settingsEnvironment(for: "media")!.settings) }

    @Test func aPlayingTrackIsOfferedToTheLockScreen() async {
        await harness.registry.bootstrap()
        #expect(harness.lockScreen.current == nil)
        source.emit(AdapterLines.track())
        #expect(harness.lockScreen.current?.module == "media")
        #expect(harness.lockScreen.current?.priority == .normal)
    }

    @Test func itStaysThroughATrackChangeAndLeavesWhenPlaybackHides() async {
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        source.emit(AdapterLines.empty)
        #expect(harness.lockScreen.current != nil)
        harness.scheduler.advance(by: .milliseconds(300))
        #expect(harness.lockScreen.current == nil)
    }

    @Test func aPausedTrackLeavesAfterTheGrace() async {
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        source.emit(AdapterLines.playing(false))
        harness.scheduler.advance(by: .milliseconds(4900))
        #expect(harness.lockScreen.current != nil)
        harness.scheduler.advance(by: .milliseconds(100))
        #expect(harness.lockScreen.current == nil)
    }

    @Test func theLiveActivitySettingDoesNotDecideWhatTheLockScreenOffers() async {
        harness.settings.set(false, for: keys.showActivity)
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        #expect(harness.activities.current == nil)
        #expect(harness.lockScreen.current?.module == "media")
    }

    @Test func hiddenAppsAreNeverOffered() async {
        harness.settings.set(["com.example.Player"], for: keys.hiddenApps)
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        #expect(harness.lockScreen.current == nil)
    }

    @Test func aFailingSourceWithdrawsIt() async {
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        source.fail("gave up")
        #expect(harness.lockScreen.current == nil)
    }

    @Test func disablingWithdrawsItAndEnablingAgainOffersTheNextTrack() async {
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        await harness.registry.setEnabled(false, for: "media")
        #expect(harness.lockScreen.current == nil)

        await harness.registry.setEnabled(true, for: "media")
        source.emit(AdapterLines.track("Next"))
        #expect(harness.lockScreen.current?.module == "media")
    }
}
