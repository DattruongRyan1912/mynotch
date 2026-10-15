import AppKit
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import Observation
import SwiftUI
import Testing
@testable import LockScreenModule

/// What the lock screen told a view about lyrics and about whether it can be seen, for the test to read.
final class EnvironmentProbe {
    var lyricsEnabled: [Bool] = []
    var onScreen: [Bool] = []
}

struct EnvironmentProbeView: View {
    @Environment(\.lockScreenLyricsEnabled) private var lyricsEnabled
    @Environment(\.notchIsOnScreen) private var isOnScreen
    let probe: EnvironmentProbe

    var body: some View {
        probe.lyricsEnabled.append(lyricsEnabled)
        probe.onScreen.append(isOnScreen)
        return Text("probe")
    }
}

/// "Hiện lời bài hát trên màn hình khoá": a switch of its own, and what the lock screen says about being seen, so that the lyric
/// lines stop ticking and sweeping when the display sleeps.
@Suite struct LockScreenLyricsTests {
    nonisolated final class Flag: @unchecked Sendable {
        nonisolated(unsafe) var isSet = false
    }

    func windowWhileLocked(_ fixture: LockScreenFixture, probe: EnvironmentProbe) async -> FakeLockScreenWindow {
        fixture.harness.lockScreen.set(AnyView(EnvironmentProbeView(probe: probe)), priority: .normal, isInteractive: true, from: "media")
        await fixture.enable()
        await fixture.lock()
        return fixture.factory.windows[0]
    }

    /// A fresh hosting view, which evaluates the root view as it is now.
    func render(_ window: FakeLockScreenWindow, into probe: EnvironmentProbe) {
        probe.lyricsEnabled = []
        probe.onScreen = []
        let hosting = NSHostingView(rootView: window.content)
        hosting.frame = CGRect(x: 0, y: 0, width: 340, height: 80)
        hosting.layoutSubtreeIfNeeded()
    }

    // MARK: the setting

    @Test func theLyricsSettingIsOnByDefaultKeptAndNotTheOtherSwitches() async {
        let fixture = LockScreenFixture()
        await fixture.enable()
        let keys = fixture.keys
        #expect(keys.showLyrics.defaultValue == true)
        #expect(fixture.settings.value(keys.showLyrics))
        fixture.settings.set(false, for: keys.showLyrics)
        #expect(!fixture.settings.value(keys.showLyrics))
        #expect(fixture.settings.value(keys.showMedia) && fixture.settings.value(keys.showMediaControls), "the others are their own")
        fixture.harness.settings.reset(keys.showLyrics)
        #expect(fixture.settings.value(keys.showLyrics))
    }

    @Test func theControlsSwitchDoesNotMoveTheLyricsSwitch() async {
        let fixture = LockScreenFixture()
        await fixture.enable()
        fixture.settings.set(false, for: fixture.keys.showMediaControls)
        #expect(fixture.settings.value(fixture.keys.showLyrics))
        fixture.settings.set(false, for: fixture.keys.showLyrics)
        fixture.settings.set(true, for: fixture.keys.showMediaControls)
        #expect(!fixture.settings.value(fixture.keys.showLyrics))
    }

    @Test func theSwitchHasItsOwnNameAndSaysItIsOnlyTheLyrics() {
        #expect(LockScreenSettingsView.lyricsTitle == "Hiện lời bài hát trên màn hình khoá")
        #expect(LockScreenSettingsView.lyricsExplanation.contains("dòng đang hát"))
        #expect(LockScreenSettingsView.lyricsExplanation.contains("dòng kế tiếp"))
        #expect(LockScreenSettingsView.lyricsExplanation.contains("công khai"))
    }

    // MARK: what the view is told

    @Test func theViewIsToldWhetherItMayShowLyrics() async {
        let fixture = LockScreenFixture()
        let probe = EnvironmentProbe()
        let window = await windowWhileLocked(fixture, probe: probe)
        render(window, into: probe)
        #expect(probe.lyricsEnabled.last == true)

        fixture.settings.set(false, for: fixture.keys.showLyrics)
        render(window, into: probe)
        #expect(probe.lyricsEnabled.last == false)

        fixture.settings.set(true, for: fixture.keys.showLyrics)
        render(window, into: probe)
        #expect(probe.lyricsEnabled.last == true)
    }

    @Test func theLyricsSettingNeverChangesWhetherThePanelTakesClicks() async {
        let fixture = LockScreenFixture()
        let probe = EnvironmentProbe()
        let window = await windowWhileLocked(fixture, probe: probe)
        #expect(window.takesClicks)
        fixture.settings.set(false, for: fixture.keys.showLyrics)
        for _ in 0..<50 { await Task.yield() }
        #expect(window.takesClicks)
    }

    // MARK: being seen

    @Test func lockedWithTheDisplayOnTheViewIsToldItCanBeSeen() async {
        let fixture = LockScreenFixture()
        let probe = EnvironmentProbe()
        let window = await windowWhileLocked(fixture, probe: probe)
        render(window, into: probe)
        #expect(probe.onScreen.last == true)
    }

    @Test func whenTheDisplaySleepsTheViewIsToldAtOnceNotAfterTheHideDelay() async {
        let fixture = LockScreenFixture()
        let probe = EnvironmentProbe()
        let window = await windowWhileLocked(fixture, probe: probe)
        await fixture.sleepDisplay()
        #expect(!fixture.log.entries.contains { $0.hasPrefix("dismiss") }, "the window is still up, for the moment the screen fades")
        render(window, into: probe)
        #expect(probe.onScreen.last == false)

        fixture.harness.scheduler.advance(by: LockScreenModule.hideDelay)
        #expect(fixture.log.entries.contains("dismiss \(window.windowNumber)"))
    }

    @Test func aDisplayThatWakesAgainBringsTheSameViewBackToLife() async {
        let fixture = LockScreenFixture()
        let probe = EnvironmentProbe()
        let window = await windowWhileLocked(fixture, probe: probe)
        await fixture.sleepDisplay()
        await fixture.wakeDisplay()
        render(window, into: probe)
        #expect(probe.onScreen.last == true)
        fixture.harness.scheduler.advance(by: LockScreenModule.hideDelay)
        #expect(fixture.factory.windows.count == 1)
        #expect(!fixture.log.entries.contains { $0.hasPrefix("dismiss") })
    }

    @Test func unlockingTellsTheViewAtOnce() async {
        let fixture = LockScreenFixture()
        let probe = EnvironmentProbe()
        let window = await windowWhileLocked(fixture, probe: probe)
        await fixture.unlock()
        render(window, into: probe)
        #expect(probe.onScreen.last == false)
    }

    @Test func theNextLockAfterAnUnlockIsSeenAgain() async {
        let fixture = LockScreenFixture()
        let probe = EnvironmentProbe()
        _ = await windowWhileLocked(fixture, probe: probe)
        await fixture.unlock()
        fixture.harness.scheduler.advance(by: LockScreenModule.hideDelay)
        await fixture.lock()
        let window = fixture.factory.windows[1]
        render(window, into: probe)
        #expect(probe.onScreen.last == true)
    }

    @Test func stoppingTheModuleLeavesNothingSeen() async {
        let fixture = LockScreenFixture()
        let probe = EnvironmentProbe()
        let window = await windowWhileLocked(fixture, probe: probe)
        await fixture.harness.registry.setEnabled(false, for: "lockscreen")
        render(window, into: probe)
        #expect(probe.onScreen.last == false)
    }

    @Test func seenFlagIsObservableSoAViewAlreadyOnScreenFollowsIt() {
        let presence = LockScreenPresence()
        let invalidated = Flag()
        withObservationTracking { _ = presence.isOnScreen } onChange: { invalidated.isSet = true }
        presence.set(false)
        #expect(!invalidated.isSet, "no change, no word")
        presence.set(true)
        #expect(invalidated.isSet)
    }

    @Test func thePanelHasRoomForTheLyricLinesUnderTheTrack() {
        // The card's inner height: two lyric rows (about 34) over the cover row (40), the bar (3) and the gaps (12), plus the padding.
        #expect(LockScreenPanel.size.height >= 112)
        #expect(LockScreenPanel.size.width == 340)
    }
}
