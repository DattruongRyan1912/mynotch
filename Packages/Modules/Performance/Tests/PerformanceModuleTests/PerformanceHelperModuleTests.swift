import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import PerformanceModule

/// What the module does about the fan helper: with fakes only, so nothing is ever registered and no daemon is called.
@Suite struct PerformanceHelperModuleTests {
    typealias Fixture = PerformanceModuleTests.Fixture

    @Test func startingWithNoHelperInstalledRegistersAndCallsNothing() async {
        let rig = HelperRig(status: .notRegistered)
        _ = await Fixture(rig: rig)
        await settle { rig.manager.phase == .notInstalled }
        #expect(rig.manager.phase == .notInstalled)
        #expect(rig.registration.calls.isEmpty)
        #expect(rig.client.pingCount == 0)
    }

    @Test func startingChecksAnInstalledHelperOnceAndLeavesItAlone() async {
        let rig = HelperRig(status: .enabled)
        let f = await Fixture(rig: rig)
        await settle { rig.manager.phase == .running(.matching) }
        #expect(rig.manager.phase == .running(.matching))
        #expect(rig.client.pingCount == 1)
        #expect(rig.registration.calls.isEmpty)
        #expect(f.harness.registry.state(of: "performance") == .running)
    }

    @Test func startingWithAHelperThatIsNotTheBundledOneRegistersItAgain() async {
        let rig = HelperRig(status: .enabled, pings: [.success(.oldBuild), .success(.matching)])
        _ = await Fixture(rig: rig)
        await settle { rig.manager.phase == .running(.matching) }
        #expect(rig.registration.calls == [.unregister, .register])
        #expect(rig.manager.phase == .running(.matching))
    }

    @Test func turningTheModuleOffAndOnAgainDoesNotRegisterAgainInTheSameLaunch() async {
        let rig = HelperRig(status: .enabled, pings: [.success(.oldBuild)])
        let f = await Fixture(rig: rig)
        await settle { rig.manager.phase == .failed(FanHelperManager.stillOutdated) }
        let calls = rig.registration.calls
        #expect(calls == [.unregister, .register])
        await f.harness.registry.setEnabled(false, for: "performance")
        await f.harness.registry.setEnabled(true, for: "performance")
        await idle()
        #expect(rig.registration.calls == calls)
    }

    @Test func turningTheModuleOffNeverRemovesTheHelper() async {
        let rig = HelperRig(status: .enabled)
        let f = await Fixture(rig: rig)
        await settle { rig.manager.phase == .running(.matching) }
        await f.harness.registry.setEnabled(false, for: "performance")
        #expect(rig.registration.calls.isEmpty)
    }

    @Test func openingTheTabLooksAtTheHelperButNeverRegistersIt() async {
        let rig = HelperRig(status: .notRegistered)
        let f = await Fixture(rig: rig)
        await settle { rig.manager.phase == .notInstalled }
        rig.registration.status = .requiresApproval
        f.appear()
        await settle { rig.manager.phase == .needsApproval }
        #expect(rig.manager.phase == .needsApproval, "the tab noticed the user's change in System Settings")
        #expect(rig.registration.calls.isEmpty)
    }

    @Test func theTabHasTheHelpersStateToShow() async {
        let rig = HelperRig(status: .requiresApproval)
        let f = await Fixture(rig: rig)
        #expect(f.module.state.helper === rig.manager)
    }

    @Test func theSettingsRowsAreGivenTheHelper() async throws {
        let f = await Fixture()
        let environment = try #require(f.harness.settingsEnvironment(for: "performance"))
        let view = try #require(f.module.makeSettingsView(environment))
        #expect(String(describing: view).hasPrefix("AnyView(PerformanceSettingsView("))
    }

    @Test func theSettingsViewBuildsInEveryPhaseOfTheHelper() async {
        for (name, make) in PerformanceTabLayoutTests.helperRigs {
            let rig = make()
            await rig.manager.refresh()
            let view = PerformanceSettingsView(
                stripTemperature: .constant(false), stripMemory: .constant(true), helper: rig.manager, probe: .constant(.never), fanMode: .constant(.curve), curveStart: .constant(55), curveFull: .constant(85),
                curve: FanCurveRunner(helper: rig.manager, activity: FakeActivity()), readAppFans: { [] }
            )
            let size = NSHostingView(rootView: Form { view }.formStyle(.grouped).frame(width: 480)).fittingSize
            #expect(size.height > 100, "\(name)")
        }
    }
}
