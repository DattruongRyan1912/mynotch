import EqualizerAudio
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import EqualizerModule

/// What the user is told and what the engine does when the audio does not work: a missing permission and a device that
/// cannot be set up. The rule for both is that the user is never left in silence, so the engine is stopped at once.
@Suite struct EqualizerStatusTests {
    let defaults = makeIsolatedDefaults()
    let state: EqualizerState
    let engine = FakeEngine()
    let module: EqualizerModule
    let harness: RegistryHarness

    init() {
        state = EqualizerState(settings: SettingsStore(defaults: defaults))
        module = EqualizerModule(state: state, engine: engine, isEqMacRunning: { false })
        harness = RegistryHarness([module])
    }

    func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() { await Task.yield() }
    }

    /// The module running with the switch on and the engine started.
    func startedAndOn() async {
        await harness.registry.bootstrap()
        state.isEnabled = true
        await settle { engine.startCount == 1 }
    }

    /// The same, after the engine said the permission is probably missing.
    func pausedForPermission() async {
        await startedAndOn()
        engine.emit(.devices(["MacBook Pro Speakers"]))
        engine.emit(.permissionLikelyDenied)
    }

    // MARK: The status line

    @Test func theLineNamesTheDevicesBeingTuned() async {
        await startedAndOn()
        engine.emit(.devices(["MacBook Pro Speakers", "AirPods của Ryan"]))
        #expect(module.status.line == .processing(["MacBook Pro Speakers", "AirPods của Ryan"]))
        #expect(module.status.line.text == "Đang chỉnh: MacBook Pro Speakers, AirPods của Ryan")
    }

    @Test func theLineWaitsForSoundWhenNoDeviceIsPlaying() async {
        await startedAndOn()
        #expect(module.status.line.text == "EQ đang chờ âm thanh")
        engine.emit(.devices(["MacBook Pro Speakers"]))
        engine.emit(.devices([]))
        #expect(module.status.line == .waiting)
        #expect(module.status.line.text == "EQ đang chờ âm thanh")
    }

    @Test func theLineFollowsADeviceThatIsPlayingWhenTheEngineStarts() async {
        engine.playing = ["MacBook Pro Speakers"]
        await startedAndOn()
        #expect(module.status.line.text == "Đang chỉnh: MacBook Pro Speakers")
    }

    @Test func theLineSaysTheEQIsOffWhenTheSwitchIs() async {
        await harness.registry.bootstrap()
        #expect(module.status.line.text == "EQ đang tắt")
        await startedAndOn()
        state.isEnabled = false
        await settle { engine.stopCount == 1 }
        #expect(module.status.line == .off)
    }

    @Test func aLateDevicesEventAfterSwitchingOffChangesNothing() async {
        await startedAndOn()
        state.isEnabled = false
        await settle { engine.stopCount == 1 }
        engine.emit(.devices(["MacBook Pro Speakers"]))
        #expect(module.status.line == .off)
    }

    // MARK: A missing permission

    @Test func aMissingPermissionStopsTheEngineAtOnceAndKeepsTheSwitch() async {
        await pausedForPermission()
        // Synchronously, inside the event: a tap without permission mutes its device, so the original audio must be back now.
        #expect(engine.stopCount == 1)
        #expect(!engine.isRunning)
        #expect(state.isEnabled)
        #expect(module.status.phase == .needsPermission)
        #expect(module.status.line == .permission)
    }

    @Test func theHintOffersTheSettingsAndANewTry() async {
        await pausedForPermission()
        #expect(module.status.line.actions == [.openSettings, .retry])
        #expect(module.status.line.text.contains("quyền"))
    }

    @Test func whatTheEngineSaysOnItsWayDownDoesNotClearThePause() async {
        await pausedForPermission()
        // `stop()` announced `.devices([])`, and the engine may say more before it is quiet.
        #expect(module.status.phase == .needsPermission)
        engine.emit(.devices(["MacBook Pro Speakers"]))
        #expect(module.status.phase == .needsPermission)
        engine.emit(.failed("MacBook Pro Speakers: x"))
        #expect(module.status.phase == .needsPermission)
    }

    @Test func aPausedEQWithoutDevicesNeverStartsOnItsOwn() async {
        await pausedForPermission()
        for _ in 0..<30 { await Task.yield() }
        #expect(engine.startCount == 1)
        #expect(!engine.isRunning)
    }

    @Test func retryAfterAMissingPermissionRestartsTheEngine() async {
        await pausedForPermission()
        module.retry()
        #expect(engine.startCount == 2)
        #expect(engine.isRunning)
        #expect(module.status.phase == .waiting)
        #expect(module.status.line.actions.isEmpty)
        #expect(state.isEnabled)
    }

    @Test func retryAppliesTheCurrentProfileFirst() async throws {
        await pausedForPermission()
        let other = try #require(state.profiles.last)
        state.select(other.id)
        await settle { engine.applied.last == other }
        let before = engine.calls.count
        module.retry()
        // Already applied while paused, so the restart is only a start.
        #expect(Array(engine.calls.dropFirst(before)) == ["start"])
        #expect(engine.applied.last == other)
    }

    @Test func retryThatFailsAgainPausesAgainAfterTheNextVerdict() async {
        await pausedForPermission()
        module.retry()
        engine.emit(.permissionLikelyDenied)
        #expect(module.status.phase == .needsPermission)
        #expect(engine.stopCount == 2)
        #expect(!engine.isRunning)
    }

    @Test func switchingTheEQOffAndOnRestartsTheEngine() async {
        await pausedForPermission()
        state.isEnabled = false
        await settle { module.status.phase == .off }
        #expect(module.status.phase == .off)
        state.isEnabled = true
        await settle { engine.startCount == 2 }
        #expect(engine.startCount == 2)
        #expect(engine.isRunning)
        #expect(module.status.phase == .waiting)
    }

    @Test func openingTheTabAgainRestartsAPausedEngine() async {
        await pausedForPermission()
        module.tabAppeared()
        #expect(engine.startCount == 2)
        #expect(engine.isRunning)
        #expect(module.status.phase == .waiting)
    }

    @Test func openingTheTabDoesNotRestartAnEngineThatIsRunning() async {
        await startedAndOn()
        module.tabAppeared()
        module.tabAppeared()
        #expect(engine.startCount == 1)
        #expect(engine.stopCount == 0)
    }

    @Test func openingTheTabWhileTheEQIsOffDoesNothing() async {
        await harness.registry.bootstrap()
        module.tabAppeared()
        #expect(engine.calls.isEmpty)
    }

    @Test func aNewTryWhenNothingIsPausedDoesNothing() async {
        await startedAndOn()
        module.retry()
        #expect(engine.startCount == 1)
        #expect(engine.stopCount == 0)
    }

    @Test func aProfileChangeWhilePausedAppliesWithoutStarting() async throws {
        await pausedForPermission()
        state.setGain(5, band: 0)
        await settle { engine.applied.last?.gains[0] == 5 }
        #expect(engine.applied.last?.gains[0] == 5)
        #expect(engine.startCount == 1)
        #expect(module.status.phase == .needsPermission)
    }

    @Test func openSettingsAsksForTheSystemAudioPane() async {
        await pausedForPermission()
        module.actions.openSettings()
        #expect(harness.permissions.openedSettings == [.systemAudio])
    }

    @Test func theTabActionsAreTheModulesOwn() async {
        await pausedForPermission()
        module.actions.retry()
        #expect(engine.startCount == 2)
        engine.emit(.permissionLikelyDenied)
        module.actions.appeared()
        #expect(engine.startCount == 3)
    }

    // MARK: A device that cannot be set up

    @Test func aFailedDeviceStopsTheEngineAndShowsTheReason() async {
        await startedAndOn()
        engine.emit(.devices(["MacBook Pro Speakers"]))
        engine.emit(.failed("Loa Bluetooth: the tap's channels do not match"))
        #expect(engine.stopCount == 1)
        #expect(!engine.isRunning)
        #expect(state.isEnabled)
        #expect(module.status.phase == .failed("Loa Bluetooth: the tap's channels do not match"))
        #expect(module.status.line.text.contains("Loa Bluetooth: the tap's channels do not match"))
        #expect(module.status.line.actions == [.retry])
    }

    @Test func retryAfterAFailureRestartsTheEngine() async {
        await startedAndOn()
        engine.emit(.failed("Loa: x"))
        module.retry()
        #expect(engine.startCount == 2)
        #expect(engine.isRunning)
        #expect(module.status.phase == .waiting)
    }

    @Test func aFailureDoesNotRestartWhenTheTabOpens() async {
        await startedAndOn()
        engine.emit(.failed("Loa: x"))
        module.tabAppeared()
        #expect(engine.startCount == 1)
        #expect(module.status.phase == .failed("Loa: x"))
    }

    @Test func aSecondFailureKeepsTheFirstReason() async {
        await startedAndOn()
        engine.emit(.failed("Loa A: x"))
        engine.emit(.failed("Loa B: y"))
        #expect(module.status.phase == .failed("Loa A: x"))
        #expect(engine.stopCount == 1)
    }

    @Test func switchingOffAndOnClearsAFailure() async {
        await startedAndOn()
        engine.emit(.failed("Loa: x"))
        state.isEnabled = false
        await settle { module.status.phase == .off }
        state.isEnabled = true
        await settle { engine.startCount == 2 }
        #expect(engine.startCount == 2)
        #expect(module.status.phase == .waiting)
    }

    @Test func aFailureOutranksTheEqMacWarning() async {
        let eqMac = EqualizerModule(state: state, engine: engine, isEqMacRunning: { true })
        let harness = RegistryHarness([eqMac])
        await harness.registry.bootstrap()
        state.isEnabled = true
        await settle { engine.startCount == 1 }
        #expect(eqMac.status.line == .eqMac)
        engine.emit(.failed("Loa: x"))
        #expect(eqMac.status.line == .failed("Loa: x"))
        engine.emit(.devices([]))
        #expect(eqMac.status.line == .failed("Loa: x"))
    }

    // MARK: The life cycle clears it

    @Test func stoppingTheModuleClearsThePause() async {
        await pausedForPermission()
        await harness.registry.setEnabled(false, for: "equalizer")
        #expect(module.status.phase == .off)
    }

    @Test func startingTheModuleAgainStartsClean() async {
        await pausedForPermission()
        await harness.registry.setEnabled(false, for: "equalizer")
        await harness.registry.setEnabled(true, for: "equalizer")
        // The switch was left on, and a new run of the module is a new try.
        #expect(state.isEnabled)
        #expect(engine.startCount == 2)
        #expect(engine.isRunning)
        #expect(module.status.phase == .waiting)
    }
}

/// What the line is made of, without a view.
@Suite struct EqualizerStatusLineTests {
    @Test func everyLineHasItsOwnText() {
        typealias Line = EqualizerStatus.Line
        #expect(Line.off.text == "EQ đang tắt")
        #expect(Line.waiting.text == "EQ đang chờ âm thanh")
        #expect(Line.processing(["A"]).text == "Đang chỉnh: A")
        #expect(Line.processing(["A", "B"]).text == "Đang chỉnh: A, B")
        #expect(Line.failed("lý do").text == "EQ không chạy được: lý do")
    }

    @Test func onlyTheLinesThatNeedTheUserOfferAButton() {
        typealias Line = EqualizerStatus.Line
        #expect(Line.off.actions.isEmpty)
        #expect(Line.waiting.actions.isEmpty)
        #expect(Line.processing(["A"]).actions.isEmpty)
        #expect(Line.eqMac.actions.isEmpty)
        #expect(Line.permission.actions == [.openSettings, .retry])
        #expect(Line.failed("x").actions == [.retry])
    }

    @Test func theButtonsAreNamedInVietnamese() {
        #expect(EqualizerStatus.Action.openSettings.title == "Mở System Settings")
        #expect(EqualizerStatus.Action.retry.title == "Thử lại")
    }

    @Test func warningsAreTheLinesThatCostTheUserSomething() {
        typealias Line = EqualizerStatus.Line
        #expect(Line.permission.isWarning)
        #expect(Line.failed("x").isWarning)
        #expect(Line.eqMac.isWarning)
        #expect(!Line.off.isWarning)
        #expect(!Line.waiting.isWarning)
        #expect(!Line.processing(["A"]).isWarning)
    }
}

/// What the Settings rows show, without a view: the hint is there as in the tab, and the permission row never doubles its button.
@Suite struct EqualizerSettingsPlanTests {
    typealias Line = EqualizerStatus.Line

    @Test func aMissingPermissionShowsTheHintWithBothButtonsAndTheRowStepsAside() {
        let plan = EqualizerSettingsView.plan(line: .permission, isRunning: true, isEnabled: true)
        #expect(plan.status == .permission)
        #expect(plan.status?.actions == [.openSettings, .retry])
        #expect(!plan.rowOffersSettings)
    }

    @Test func aFailureShowsItsReasonWithANewTryAndTheRowKeepsItsButton() {
        let plan = EqualizerSettingsView.plan(line: .failed("Loa: x"), isRunning: true, isEnabled: true)
        #expect(plan.status == .failed("Loa: x"))
        #expect(plan.status?.actions == [.retry])
        #expect(plan.rowOffersSettings)
    }

    @Test func whatIsPlayingIsShownWithoutButtons() {
        let plan = EqualizerSettingsView.plan(line: .processing(["A"]), isRunning: true, isEnabled: true)
        #expect(plan.status == .processing(["A"]))
        #expect(plan.status?.actions.isEmpty == true)
        #expect(plan.rowOffersSettings)
    }

    @Test func nothingIsShownWhileTheModuleIsNotRunning() {
        let plan = EqualizerSettingsView.plan(line: .permission, isRunning: false, isEnabled: true)
        #expect(plan.status == nil)
        #expect(plan.rowOffersSettings)
    }

    @Test func nothingIsShownWhileTheSwitchIsOff() {
        let plan = EqualizerSettingsView.plan(line: .failed("Loa: x"), isRunning: true, isEnabled: false)
        #expect(plan.status == nil)
        #expect(plan.rowOffersSettings)
    }
}
