import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import LockScreenModule

/// Waits on the main actor, where the module's observation runs, until `condition` holds. The limit only matters when
/// something is wrong, so it is generous.
@discardableResult
func waitUntil(seconds: Double = 60, _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while !condition() {
        if ContinuousClock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

/// A view that says what the lock screen told it about controls, for the test to read.
final class ControlsProbe {
    var seen: [Bool] = []
}

struct ControlsProbeView: View {
    @Environment(\.lockScreenControlsEnabled) private var controlsEnabled
    let probe: ControlsProbe

    var body: some View {
        probe.seen.append(controlsEnabled)
        return Text("probe")
    }
}

/// "Điều khiển nhạc trên màn hình khoá": whether the media view has buttons, and so whether the panel takes clicks.
@Suite struct LockScreenControlsTests {
    func windowWhileLocked(_ fixture: LockScreenFixture) async -> FakeLockScreenWindow {
        await fixture.lock()
        return fixture.factory.windows[0]
    }

    // MARK: the setting

    @Test func theControlsSettingIsOnByDefaultAndKept() async {
        let fixture = LockScreenFixture()
        await fixture.enable()
        let keys = fixture.keys
        #expect(keys.showMediaControls.defaultValue == true)
        #expect(fixture.settings.value(keys.showMediaControls))
        fixture.settings.set(false, for: keys.showMediaControls)
        #expect(!fixture.settings.value(keys.showMediaControls))
        #expect(fixture.settings.value(keys.showMedia), "the other switch is its own")
        fixture.harness.settings.reset(keys.showMediaControls)
        #expect(fixture.settings.value(keys.showMediaControls))
    }

    @Test func theSwitchHasItsOwnNameAndTheWarningAndTheMediaRowNoLongerWarns() {
        #expect(LockScreenSettingsView.controlsTitle == "Điều khiển nhạc trên màn hình khoá")
        #expect(LockScreenSettingsView.controlsExplanation.contains("bấm"))
        #expect(LockScreenSettingsView.controlsExplanation.contains("phát/dừng"))
        #expect(!LockScreenSettingsView.mediaExplanation.contains("bấm"))
    }

    // MARK: the panel takes clicks only for controls

    @Test func aViewWithControlsMakesThePanelTakeClicksWhileTheSettingIsOn() async {
        let fixture = LockScreenFixture()
        fixture.offer("media", isInteractive: true)
        await fixture.enable()
        let window = await windowWhileLocked(fixture)
        #expect(window.takesClicks)
    }

    @Test func withTheSettingOffThePanelIgnoresClicksEntirely() async {
        let fixture = LockScreenFixture()
        fixture.offer("media", isInteractive: true)
        await fixture.enable()
        fixture.settings.set(false, for: fixture.keys.showMediaControls)
        let window = await windowWhileLocked(fixture)
        #expect(!window.takesClicks)
    }

    @Test func aViewWithNoControlsNeverTakesClicksWhateverTheSetting() async {
        let fixture = LockScreenFixture()
        fixture.offer("timer", isInteractive: false)
        await fixture.enable()
        let window = await windowWhileLocked(fixture)
        #expect(fixture.settings.value(fixture.keys.showMediaControls))
        #expect(!window.takesClicks)
    }

    @Test func theSettingIsFollowedWhileThePanelIsUp() async {
        let fixture = LockScreenFixture()
        fixture.offer("media", isInteractive: true)
        await fixture.enable()
        let window = await windowWhileLocked(fixture)
        #expect(window.takesClicks)
        fixture.settings.set(false, for: fixture.keys.showMediaControls)
        #expect(await waitUntil { !window.takesClicks })
        fixture.settings.set(true, for: fixture.keys.showMediaControls)
        #expect(await waitUntil { window.takesClicks })
    }

    @Test func whatIsShownDecidesWhileThePanelIsUp() async {
        let fixture = LockScreenFixture()
        fixture.offer("media", isInteractive: true)
        await fixture.enable()
        let window = await windowWhileLocked(fixture)
        #expect(window.takesClicks)
        // A timer outranks the music: nothing to press is on show, so clicks pass through.
        fixture.offer("timer", priority: .high, isInteractive: false)
        #expect(await waitUntil { !window.takesClicks })
        fixture.harness.lockScreen.clear(from: "timer")
        #expect(await waitUntil { window.takesClicks })
    }

    @Test func turningTheMediaViewOffEndsTheClicksToo() async {
        let fixture = LockScreenFixture()
        fixture.offer("media", isInteractive: true)
        fixture.offer("timer", priority: .normal, isInteractive: false)
        await fixture.enable()
        let window = await windowWhileLocked(fixture)
        // Of two entries of the same priority the one added last is shown: the timer, which has nothing to press.
        #expect(!window.takesClicks)
        fixture.settings.set(false, for: fixture.keys.showTimer)
        #expect(await waitUntil { window.takesClicks })
        fixture.settings.set(false, for: fixture.keys.showMedia)
        #expect(await waitUntil { !window.takesClicks })
    }

    @Test func aPanelThatIsGoneIsNotWatchedAnyMore() async {
        let fixture = LockScreenFixture()
        fixture.offer("media", isInteractive: true)
        await fixture.enable()
        let window = await windowWhileLocked(fixture)
        await fixture.unlock()
        fixture.harness.scheduler.advance(by: LockScreenModule.hideDelay)
        window.takesClicks = false
        fixture.settings.set(false, for: fixture.keys.showMediaControls)
        fixture.settings.set(true, for: fixture.keys.showMediaControls)
        for _ in 0..<50 { await Task.yield() }
        #expect(!window.takesClicks, "a dismissed window is left alone")
    }

    // MARK: what the view is told

    func render(_ content: AnyView) {
        let hosting = NSHostingView(rootView: content)
        hosting.frame = CGRect(x: 0, y: 0, width: 340, height: 80)
        hosting.layoutSubtreeIfNeeded()
    }

    @Test func theViewIsToldWhetherItMayDrawItsControls() async {
        let fixture = LockScreenFixture()
        let probe = ControlsProbe()
        fixture.harness.lockScreen.set(AnyView(ControlsProbeView(probe: probe)), priority: .normal, isInteractive: true, from: "media")
        await fixture.enable()
        let window = await windowWhileLocked(fixture)
        render(window.content)
        #expect(probe.seen.last == true)

        fixture.settings.set(false, for: fixture.keys.showMediaControls)
        probe.seen = []
        render(window.content)
        #expect(probe.seen.last == false)
    }

    @Test func theRootViewShowsNothingWhenNothingIsAllowed() async {
        let fixture = LockScreenFixture()
        let probe = ControlsProbe()
        fixture.harness.lockScreen.set(AnyView(ControlsProbeView(probe: probe)), priority: .normal, isInteractive: true, from: "media")
        await fixture.enable()
        let window = await windowWhileLocked(fixture)
        fixture.settings.set(false, for: fixture.keys.showMedia)
        probe.seen = []
        render(window.content)
        #expect(probe.seen.isEmpty)
    }
}
