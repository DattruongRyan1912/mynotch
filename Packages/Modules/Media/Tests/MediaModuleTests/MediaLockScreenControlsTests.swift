import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import MediaModule

/// The lock screen's buttons, through the module with a fake source: the same commands, looks and rules as the Media tab's.
@Suite final class MediaLockScreenControlsTests {
    let source = FakeNowPlayingSource()
    let module: MediaModule
    let harness: RegistryHarness
    let storageBase: URL

    init() {
        module = MediaModule(
            source: source, spectrum: FakeSpectrumSource(), lyricsClient: FakeHTTPClient(), tokens: FakeTokenStore(),
            signIn: FakeAppleMusicSignIn(), lookUpApp: { _ in nil }
        )
        harness = RegistryHarness([module])
        storageBase = harness.storageRoot.caches.deletingLastPathComponent()
    }

    deinit { try? FileManager.default.removeItem(at: storageBase) }

    var store: NowPlayingStore { module.store }
    var transport: LockScreenTransport { module.lockScreenTransport }

    func play(_ extra: [String: Any] = [:], bundle: String = "com.example.Player", playing: Bool = true) {
        source.emit(AdapterLines.track(playing: playing, bundle: bundle, extra: extra))
    }

    @Test func thePlayPauseButtonSendsTheTabsCommand() async {
        await harness.registry.bootstrap()
        play()
        transport.togglePlayPause()
        #expect(source.sent == [.togglePlayPause])
    }

    @Test func previousAndNextSendTheTabsCommandsInTheTabsOrder() async {
        await harness.registry.bootstrap()
        play()
        transport.skipBack()
        transport.skipForward()
        #expect(source.sent == [.previousTrack, .nextTrack])
    }

    @Test func theyAreTheTabsButtonsPressedNotACopyOfThem() async {
        await harness.registry.bootstrap()
        play()
        module.press(.previous)
        transport.skipBack()
        #expect(source.sent == [.previousTrack, .previousTrack])
    }

    @Test func aSkipThePlayerProhibitsIsNotSentAndTheButtonsAreFaded() async {
        await harness.registry.bootstrap()
        play(["prohibitsSkip": true])
        #expect(!transport.previous.isEnabled && !transport.next.isEnabled)
        transport.skipBack()
        transport.skipForward()
        #expect(source.sent.isEmpty)
        transport.togglePlayPause()
        #expect(source.sent == [.togglePlayPause], "play and pause are never refused")
    }

    @Test func aBrowsersSkipIsNotRefusedByItsFlagBecauseItMayGoToTheExtension() async {
        await harness.registry.bootstrap()
        play(["prohibitsSkip": true], bundle: "com.google.Chrome")
        #expect(transport.previous.isEnabled && transport.next.isEnabled)
        transport.skipForward()
        #expect(source.sent == [.nextTrack])
    }

    @Test func theLooksAreTheTabsLooks() async {
        await harness.registry.bootstrap()
        play()
        let context = store.controlContext(hasVolume: false, volumeIsOpen: false)
        #expect(transport.previous == MediaControlButton.previous.look(in: context))
        #expect(transport.next == MediaControlButton.next.look(in: context))
    }

    @Test func thePlayButtonShowsWhatPressingItWillDo() async {
        await harness.registry.bootstrap()
        play()
        #expect(transport.isPlaying)
        source.emit(AdapterLines.playing(false))
        #expect(!transport.isPlaying)
    }

    @Test func throughTheEmptyStateBetweenTwoTracksTheButtonDoesNotFlip() async {
        await harness.registry.bootstrap()
        play()
        source.emit(AdapterLines.empty)
        #expect(transport.isPlaying, "the activity's snapshot keeps the last track, so the lock screen does too")
    }

    @Test func theViewFitsUnderTheNotchInTheRoomThePanelGivesIt() async {
        await harness.registry.bootstrap()
        play()
        let hosting = NSHostingView(rootView: NowPlayingLockScreenView(transport: transport).frame(width: 308))
        // The lock screen's card is 56 tall at least and adds 8 above and below; the panel is 80 tall, so 72 is the most.
        #expect(hosting.fittingSize.height + 16 <= 72)
        #expect(hosting.fittingSize.height >= 40, "the cover at least")
    }
}
