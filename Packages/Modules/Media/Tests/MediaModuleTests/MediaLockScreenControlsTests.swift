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
        // Without lyrics the card is as short as when the panel was 80 tall (the card is 56 tall at least and adds 8 above and below,
        // so 72 was the most). The panel is 112 tall now, for the lyric lines; `MediaLockScreenLyricsTests` checks the card with them.
        #expect(hosting.fittingSize.height + 16 <= 72)
        #expect(hosting.fittingSize.height >= 40, "the cover at least")
    }

    // MARK: the buttons as the view draws them

    @Test func theRowIsPreviousPlayPauseNextAndEachPressDoesItsOwnThing() async {
        await harness.registry.bootstrap()
        play()
        let controls = transport.controls
        #expect(controls.map(\.kind) == [.previous, .playPause, .next])
        controls[0].perform()
        #expect(source.sent == [.previousTrack])
        controls[1].perform()
        #expect(source.sent == [.previousTrack, .togglePlayPause])
        controls[2].perform()
        #expect(source.sent == [.previousTrack, .togglePlayPause, .nextTrack])
    }

    @Test func theRowsLooksAreThoseOfTheButtonsItDraws() async {
        await harness.registry.bootstrap()
        play()
        let controls = transport.controls
        #expect(controls[0].look == transport.previous)
        #expect(controls[1].look.symbol == "pause.fill" && controls[1].look.isEnabled)
        #expect(controls[2].look == transport.next)
        source.emit(AdapterLines.playing(false))
        #expect(transport.controls[1].look.symbol == "play.fill")
    }

    @Test func theRowsSkipsAreFadedWhenThePlayerProhibitsThem() async {
        await harness.registry.bootstrap()
        play(["prohibitsSkip": true])
        let controls = transport.controls
        #expect(!controls[0].look.isEnabled && !controls[2].look.isEnabled)
        #expect(controls[1].look.isEnabled)
        controls[0].perform()
        controls[2].perform()
        #expect(source.sent.isEmpty)
    }

    @Test func theLockScreenIsOfferedAViewWithButtonsSoItsPanelMayTakeClicks() async {
        await harness.registry.bootstrap()
        play()
        #expect(harness.lockScreen.current?.module == "media")
        #expect(harness.lockScreen.current?.isInteractive == true)
    }

    // MARK: the rendered view

    /// How many bright pixels the view draws in the strip where the buttons are (right of the title, above the progress bar), on
    /// black. The title is short, so nothing but a button can be there.
    func ink<V: View>(in view: V) -> Int {
        let renderer = ImageRenderer(content: view.frame(width: 308, height: 50).background(Color.black).environment(\.colorScheme, .dark))
        renderer.scale = 1
        guard let image = renderer.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return -1 }
        let (width, height) = (image.width, image.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return -1 }
        var count = 0
        for y in 0..<min(height, 44) {
            for x in 200..<min(width, 308) where bytes[(y * width + x) * 4 + 1] > 90 { count += 1 }
        }
        return count
    }

    @Test func theViewDrawsItsButtonsWhileTheLockScreenAllowsControls() async {
        await harness.registry.bootstrap()
        play()
        let on = ink(in: NowPlayingLockScreenView(transport: transport))
        #expect(on > 40, "three symbols are drawn right of the title")
    }

    @Test func withTheLockScreensControlsOffTheViewDrawsNoButton() async {
        await harness.registry.bootstrap()
        play()
        let off = ink(in: NowPlayingLockScreenView(transport: transport).environment(\.lockScreenControlsEnabled, false))
        #expect(off == 0)
    }
}
