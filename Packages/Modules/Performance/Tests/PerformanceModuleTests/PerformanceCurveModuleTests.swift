import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import PerformanceModule

/// The curve inside the module: what keeps it fed, what turns it off, and what the settings are.
@MainActor @Suite struct PerformanceCurveModuleTests {
    typealias Fixture = PerformanceModuleTests.Fixture

    static let modeKey = SettingKey("module.performance.fanMode", default: FanMode.apple)
    static let probeKey = SettingKey("module.performance.fanProbe", default: FanProbeOutcome.never)

    static func probed(_ verdict: FanProbeOutcome.Verdict) -> FanProbeOutcome {
        FanProbeOutcome(verdict: verdict, trials: [], note: "", at: nil)
    }

    /// A module with the helper running, the curve on, and a probe result that says how to set the fans.
    func curveFixture(verdict: FanProbeOutcome.Verdict = .forced, rig: HelperRig? = nil) async -> Fixture {
        let rig = rig ?? HelperRig(status: .enabled)
        await rig.manager.refresh()
        return await Fixture(rig: rig) { harness in
            harness.settings.set(FanMode.curve, for: Self.modeKey)
            harness.settings.set(Self.probed(verdict), for: Self.probeKey)
        }
    }

    // MARK: Fed with no tab open

    @Test func theCurveKeepsTheTemperatureBeingReadWithNoTabOpen() async {
        let f = await curveFixture()
        await settle { await f.reads() >= 1 }
        #expect(f.module.state.isTabVisible == false)
        await f.advance(2)
        await settle { await f.reads() >= 2 }
        #expect(await f.reads() >= 2, "it reads every two seconds because the curve needs the temperature")
        await settle { !f.rig.client.commands.isEmpty }
        #expect(f.rig.client.commands.contains { if case .forced(FanCommandResult.allFans, _) = $0 { true } else { false } }, "and the curve told the helper what to do with the fans, all at once")
    }

    @Test func theCurveWithTheFloorProbeResultAsksForAFloor() async {
        let f = await curveFixture(verdict: .floor)
        await settle { !f.rig.client.commands.isEmpty }
        #expect(f.rig.client.commands.allSatisfy { if case .floor = $0 { true } else { false } })
    }

    @Test func withoutAProbeResultNothingIsSetAndTheCurveSaysSo() async {
        let f = await curveFixture(verdict: .notRun)
        await settle { await f.reads() >= 1 }
        await settle { !f.module.isReading }
        #expect(f.rig.client.commands.isEmpty)
        #expect(f.module.state.curve?.status == .needsProbe)
    }

    @Test func withTheCurveOnTheProbeCannotBeStartedAndNoProbeCommandCanFightTheCurve() async {
        let f = await curveFixture(verdict: .forced)
        await settle { f.rig.manager.curveIsMode }
        #expect(f.rig.manager.canProbe == false)
        let commands = f.rig.client.commands.count
        #expect(await f.rig.manager.runProbe() == nil)
        #expect(f.rig.client.commands.count == commands, "the refused probe sent nothing")
    }

    @Test func afterSwitchingBackToAppleTheProbeIsAllowedAgain() async {
        let f = await curveFixture(verdict: .forced)
        await settle { f.rig.manager.curveIsMode }
        f.harness.settings.set(FanMode.apple, for: Self.modeKey)
        await settle { !f.rig.manager.curveIsMode }
        #expect(f.rig.manager.canProbe)
    }

    @Test func theAppIsKeptAwakeWhileTheCurveIsTheMode() async {
        let f = await curveFixture()
        await settle { f.activity.isHeld }
        #expect(f.activity.isHeld)
    }

    @Test func inAppleModeNothingIsKeptAwakeOrSetOrReadHidden() async {
        let f = await Fixture(rig: HelperRig(status: .enabled))
        await f.advance(30)
        await idle()
        #expect(f.activity.isHeld == false && f.rig.client.commands.isEmpty)
        #expect(await f.reads() == 0)
    }

    // MARK: Turning it off

    @Test func switchingBackToAppleGivesTheFansBackAndStopsReadingHidden() async {
        let f = await curveFixture()
        await settle { !f.rig.client.commands.isEmpty }
        f.harness.settings.set(FanMode.apple, for: Self.modeKey)
        await settle { f.rig.client.commands.last == .auto(-1) }
        #expect(f.rig.client.commands.last == .auto(-1))
        await settle { f.harness.scheduler.pendingCount == 0 }
        #expect(f.harness.scheduler.pendingCount == 0, "nothing is read hidden any more")
        #expect(f.activity.isHeld == false)
    }

    @Test func turningTheModuleOffGivesTheFansBackBeforeItGoes() async {
        let f = await curveFixture()
        await settle { !f.rig.client.commands.isEmpty }
        await f.harness.registry.setEnabled(false, for: "performance")
        #expect(f.rig.client.commands.last == .auto(-1))
        #expect(f.activity.isHeld == false)
        #expect(f.harness.scheduler.pendingCount == 0)
    }

    @Test func turningTheModuleOffWithNothingHeldSetsNothing() async {
        let f = await Fixture(rig: HelperRig(status: .enabled))
        await f.harness.registry.setEnabled(false, for: "performance")
        #expect(f.rig.client.commands.isEmpty)
    }

    // MARK: The tab

    @Test func theTabLineSaysWhatTheCurveIsDoing() async {
        let f = await curveFixture()
        await settle { !f.rig.client.commands.isEmpty }
        await settle { !f.module.isReading }
        #expect(f.module.state.curve?.activeText != nil)
        #expect(f.module.state.curveWanted)
    }

    // MARK: The settings

    @Test func theFanSettingsStartAsApplesWith55And85() throws {
        let harness = RegistryHarness([PerformanceModule(thermal: FakeThermalReader(), memory: FakeMemoryReader(), helper: HelperRig().manager, now: { .now }, activity: FakeActivity())])
        let environment = try #require(harness.settingsEnvironment(for: "performance"))
        let keys = PerformanceSettingsKeys(environment.settings)
        #expect(keys.fanMode.name == "module.performance.fanMode" && environment.settings.value(keys.fanMode) == .apple)
        #expect(keys.curveStart.name == "module.performance.curveStart" && environment.settings.value(keys.curveStart) == 55)
        #expect(keys.curveFull.name == "module.performance.curveFull" && environment.settings.value(keys.curveFull) == 85)
        #expect(environment.settings.value(keys.fanProbe) == .never)
    }

    @Test func theTemperaturesAreHeldToTheirRangesWhenStored() throws {
        let harness = RegistryHarness([PerformanceModule(thermal: FakeThermalReader(), memory: FakeMemoryReader(), helper: HelperRig().manager, now: { .now }, activity: FakeActivity())])
        let environment = try #require(harness.settingsEnvironment(for: "performance"))
        let keys = PerformanceSettingsKeys(environment.settings)
        environment.settings.set(5, for: keys.curveStart)
        environment.settings.set(500, for: keys.curveFull)
        #expect(environment.settings.value(keys.curveStart) == 30)
        #expect(environment.settings.value(keys.curveFull) == 100)
    }

    @Test func theSettingsAreReadAsOneSetOfValuesWithTheCurveNormalised() throws {
        let harness = RegistryHarness([PerformanceModule(thermal: FakeThermalReader(), memory: FakeMemoryReader(), helper: HelperRig().manager, now: { .now }, activity: FakeActivity())])
        let environment = try #require(harness.settingsEnvironment(for: "performance"))
        let keys = PerformanceSettingsKeys(environment.settings)
        environment.settings.set(FanMode.curve, for: keys.fanMode)
        environment.settings.set(80, for: keys.curveStart)
        environment.settings.set(82, for: keys.curveFull)
        let values = keys.values(environment.settings)
        #expect(values.fanMode == .curve)
        #expect(values.curve == FanCurve(start: 80, full: 85), "full is held five above start")
        #expect(values.stripTemperature == false && values.stripMemory == false && values.probe == .never)
    }

    @Test func theProbeResultSurvivesBeingStoredAndTheMechanismFollowsTheVerdict() throws {
        let harness = RegistryHarness([PerformanceModule(thermal: FakeThermalReader(), memory: FakeMemoryReader(), helper: HelperRig().manager, now: { .now }, activity: FakeActivity())])
        let environment = try #require(harness.settingsEnvironment(for: "performance"))
        let keys = PerformanceSettingsKeys(environment.settings)
        environment.settings.set(Self.probed(.forced), for: keys.fanProbe)
        #expect(environment.settings.value(keys.fanProbe).mechanism == .forced)
        environment.settings.set(Self.probed(.floor), for: keys.fanProbe)
        #expect(environment.settings.value(keys.fanProbe).mechanism == .floor)
        for verdict in [FanProbeOutcome.Verdict.none, .inconclusive, .notRun] {
            environment.settings.set(Self.probed(verdict), for: keys.fanProbe)
            #expect(environment.settings.value(keys.fanProbe).mechanism == nil, "\(verdict)")
        }
    }

    @Test func theSettingsViewBuildsInEveryModeAndStatus() async throws {
        let rig = HelperRig(status: .enabled)
        await rig.manager.refresh()
        for mode in FanMode.allCases {
            let view = PerformanceSettingsView(
                stripTemperature: .constant(false), stripMemory: .constant(false), helper: rig.manager, probe: .constant(.never),
                fanMode: .constant(mode), curveStart: .constant(55), curveFull: .constant(85),
                curve: FanCurveRunner(helper: rig.manager, activity: FakeActivity()), readAppFans: { [] }
            )
            let size = NSHostingView(rootView: Form { view }.formStyle(.grouped).frame(width: 520)).fittingSize
            #expect(size.height > 200, "\(mode)")
        }
    }

    @Test func thePreviewDrawsWithoutTrouble() {
        for curve in [FanCurve.standard, FanCurvePreset.maximum.curve!, FanCurvePreset.cooler.curve!] {
            let size = NSHostingView(rootView: FanCurvePreview(curve: curve).frame(width: 300, height: 64)).fittingSize
            #expect(size.width > 0 && size.height > 0)
        }
    }
}
