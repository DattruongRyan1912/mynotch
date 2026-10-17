import EqualizerAudio
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import EqualizerModule

/// The module's life cycle: what it declares, what the switch and the profile do to the engine, and what it hands the app.
@Suite struct EqualizerModuleTests {
    /// The suite is emptied when it is released, so the test holds it.
    let defaults = makeIsolatedDefaults()
    let state: EqualizerState
    let engine = FakeEngine()
    let module: EqualizerModule
    let harness: RegistryHarness
    let eqMac: EqMacFlag

    init() {
        let flag = EqMacFlag()
        eqMac = flag
        state = EqualizerState(settings: SettingsStore(defaults: defaults))
        module = EqualizerModule(state: state, engine: engine, isEqMacRunning: { flag.isRunning })
        harness = RegistryHarness([module])
    }

    /// Lets the observation loop run after a change of the state.
    func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() { await Task.yield() }
    }

    func start() async {
        await harness.registry.bootstrap()
    }

    // MARK: What it declares

    @Test func descriptor() {
        let descriptor = module.descriptor
        #expect(descriptor.id == "equalizer")
        #expect(descriptor.displayName == "Âm thanh")
        #expect(descriptor.systemImage == "slider.vertical.3")
        #expect(descriptor.order == 210)
        // Off until the user switches the EQ on, so being there costs nothing.
        #expect(descriptor.defaultEnabled)
    }

    @Test func declaresThePermissionItUsesAndWhy() {
        let descriptor = module.descriptor
        #expect(descriptor.permissions.isEmpty)
        #expect(descriptor.optionalPermissions == [.systemAudio])
        #expect(descriptor.permissionReasons == [.systemAudio: "Để chỉnh âm thanh của cả máy"])
    }

    @Test func tabAsksForNoMoreThanTheNotchGivesAndTakesTheKeyboardForRenaming() async throws {
        await start()
        let tab = try #require(harness.registry.tabs.first { $0.id == "equalizer" })
        #expect(tab.title == "Âm thanh")
        #expect(tab.systemImage == "slider.vertical.3")
        #expect(tab.acceptsKeyboard)
        #expect(tab.preferredHeight == EqualizerTabView.preferredHeight)
    }

    @Test func tabFitsHeightRange() async {
        await start()
        #expect(harness.oversizedTabs.reports.isEmpty)
        #expect(EqualizerTabView.preferredHeight <= NotchTab.heightRange.upperBound)
    }

    @Test func settingsRowsExistWhetherOrNotTheModuleRuns() async {
        let environment = harness.settingsEnvironment(for: "equalizer")
        #expect(environment?.isRunning == false)
        #expect(environment.flatMap { module.makeSettingsView($0) } != nil)
    }

    // MARK: Availability

    @Test func startMakesTheModuleAvailableToTheNhacTab() async {
        #expect(!state.isAvailable)
        #expect(state.openEditor == nil)
        await start()
        #expect(state.isAvailable)
        #expect(state.openEditor != nil)
    }

    @Test func openEditorOpensOwnTab() async {
        await start()
        state.openEditor?()
        #expect(harness.presenter.openedTabs == ["equalizer"])
    }

    @Test func moduleStopStopsEngineAndClearsAvailability() async {
        await start()
        state.isEnabled = true
        await settle { engine.startCount == 1 }
        await harness.registry.setEnabled(false, for: "equalizer")
        #expect(engine.stopCount == 1)
        #expect(!engine.isRunning)
        #expect(!state.isAvailable)
        #expect(state.openEditor == nil)
        #expect(module.status.phase == .off)
        // What the engine says on its way down reaches no one.
        #expect(engine.onEvent == nil)
    }

    @Test func moduleStopStopsTheEngineEvenIfTheSwitchWasNeverOn() async {
        await start()
        await harness.registry.setEnabled(false, for: "equalizer")
        #expect(engine.stopCount == 1)
    }

    @Test func settingsChangesAfterStopDoNotStartTheEngine() async {
        await start()
        await harness.registry.setEnabled(false, for: "equalizer")
        state.isEnabled = true
        for _ in 0..<20 { await Task.yield() }
        #expect(engine.startCount == 0)
    }

    // MARK: The switch and the profile drive the engine

    @Test func switchedOffDoesNothingToTheEngine() async {
        await start()
        for _ in 0..<20 { await Task.yield() }
        #expect(engine.calls.isEmpty)
        #expect(module.status.phase == .off)
    }

    @Test func enablingStartsAndApplies() async throws {
        await start()
        state.isEnabled = true
        await settle { engine.startCount == 1 }
        #expect(engine.startCount == 1)
        #expect(engine.applied.last == state.selected)
        #expect(module.status.phase == .waiting)
        // The profile first, so the pipelines the start builds already have the right curve.
        #expect(engine.calls == ["apply", "start"])
    }

    @Test func enabledAtLaunchStartsAtOnce() async {
        state.isEnabled = true
        await start()
        #expect(engine.startCount == 1)
        #expect(engine.applied.last == state.selected)
    }

    @Test func disablingStops() async {
        await start()
        state.isEnabled = true
        await settle { engine.startCount == 1 }
        state.isEnabled = false
        await settle { engine.stopCount == 1 }
        #expect(engine.stopCount == 1)
        #expect(!engine.isRunning)
        #expect(module.status.phase == .off)
    }

    @Test func selectingProfileApplies() async throws {
        await start()
        state.isEnabled = true
        await settle { engine.startCount == 1 }
        let other = try #require(state.profiles.last)
        state.select(other.id)
        await settle { engine.applied.last == other }
        #expect(engine.applied.last == other)
        #expect(engine.startCount == 1)
        #expect(engine.stopCount == 0)
    }

    @Test func draggingASliderAppliesTheNewCurve() async {
        await start()
        state.isEnabled = true
        await settle { engine.startCount == 1 }
        state.setGain(7, band: 3)
        await settle { engine.applied.last?.gains[3] == 7 }
        #expect(engine.applied.last?.gains[3] == 7)
        state.setPreamp(-3)
        await settle { engine.applied.last?.preamp == -3 }
        #expect(engine.applied.last?.preamp == -3)
    }

    @Test func aChangeThatLeavesTheCurveAloneAppliesNothingMore() async throws {
        await start()
        state.isEnabled = true
        await settle { engine.startCount == 1 }
        let applies = engine.applied.count
        // Renaming another profile changes the list, not what the filters play.
        let other = try #require(state.profiles.last)
        #expect(state.rename(other.id, to: "Karaoke"))
        for _ in 0..<20 { await Task.yield() }
        #expect(engine.applied.count == applies)
    }

    @Test func deletingAllAppliesFlat() async throws {
        await start()
        state.isEnabled = true
        await settle { engine.startCount == 1 }
        for profile in state.profiles { state.delete(profile.id) }
        await settle { engine.applied.last?.name == "Phẳng" }
        let flat = try #require(engine.applied.last)
        #expect(flat.gains == Array(repeating: 0, count: EQProfile.frequencies.count))
        #expect(flat.preamp == 0)
        // Still on: with no profile the EQ is flat, not off.
        #expect(engine.stopCount == 0)
        #expect(engine.isRunning)
    }

    @Test func theSwitchCanBeFlippedOffAndOnAgain() async {
        await start()
        state.isEnabled = true
        await settle { engine.startCount == 1 }
        state.isEnabled = false
        await settle { engine.stopCount == 1 }
        state.isEnabled = true
        await settle { engine.startCount == 2 }
        #expect(engine.startCount == 2)
        #expect(engine.isRunning)
    }

    // MARK: eqMac

    @Test func eqMacWarningShowsWhenRunning() async {
        eqMac.isRunning = true
        await start()
        state.isEnabled = true
        await settle { engine.startCount == 1 }
        #expect(module.status.eqMacRunning)
        #expect(module.status.line == .eqMac)
        #expect(module.status.line.text == "eqMac đang chạy: hai bộ EQ sẽ chồng lên nhau. Thoát eqMac để dùng EQ của MyNotch.")
    }

    @Test func noWarningWhenEqMacIsNotRunning() async {
        await start()
        state.isEnabled = true
        await settle { engine.startCount == 1 }
        #expect(!module.status.eqMacRunning)
        #expect(module.status.line == .waiting)
    }

    @Test func eqMacIsLookedForAgainWhenTheTabAppears() async {
        await start()
        #expect(!module.status.eqMacRunning)
        eqMac.isRunning = true
        module.tabAppeared()
        #expect(module.status.eqMacRunning)
        eqMac.isRunning = false
        module.tabAppeared()
        #expect(!module.status.eqMacRunning)
    }

    @Test func noWarningWhileTheEQIsOff() async {
        eqMac.isRunning = true
        await start()
        #expect(module.status.line == .off)
    }
}

/// What the injected "is eqMac running?" answers; a class so the test can change it after the module took the closure.
final class EqMacFlag: @unchecked Sendable {
    var isRunning = false
}
