import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import EqualizerModule

/// TC-3: Module lifecycle and settings synchronization tests for Auto-Headroom.
@Suite struct AutoHeadroomModuleTests {

    let defaults: UserDefaults
    let state: EqualizerState
    let engine: FakeEngine
    let module: EqualizerModule
    let harness: RegistryHarness

    init() {
        defaults = makeIsolatedDefaults()
        state = EqualizerState(settings: SettingsStore(defaults: defaults))
        engine = FakeEngine()
        module = EqualizerModule(state: state, engine: engine, isEqMacRunning: { false })
        harness = RegistryHarness([module])
    }

    func start() async {
        await harness.registry.bootstrap()
    }

    @Test func togglingAutoHeadroomPropagatesToEngineWithoutApplyCall() async {
        await start()
        // Start engine
        state.isEnabled = true
        await settle { self.engine.isRunning }

        let initialProcessingCalls = engine.processingSettingsCalls.count
        let initialApplyCalls = engine.applied.count

        // Toggle AutoHeadroom ON
        state.isAutoHeadroomEnabled = true

        await settle {
            self.engine.processingSettingsCalls.count >= initialProcessingCalls + 1
        }

        #expect(engine.processingSettingsCalls.last?.autoHeadroom == true)
        #expect(engine.applied.count == initialApplyCalls, "Toggling autoHeadroom must not call apply(_:)")

        // Toggle AutoHeadroom OFF
        state.isAutoHeadroomEnabled = false

        await settle {
            self.engine.processingSettingsCalls.count >= initialProcessingCalls + 2
        }

        #expect(engine.processingSettingsCalls.last?.autoHeadroom == false)
        #expect(engine.applied.count == initialApplyCalls, "Toggling autoHeadroom OFF must not call apply(_:)")
    }

    @Test func restartingEngineResendsCurrentAutoHeadroomSetting() async {
        await start()
        state.isEnabled = true
        state.isAutoHeadroomEnabled = true
        await settle { self.engine.isRunning }

        #expect(engine.processingSettingsCalls.last?.autoHeadroom == true)

        // Stop engine
        state.isEnabled = false
        await settle { !self.engine.isRunning }

        // Start engine again
        state.isEnabled = true
        await settle { self.engine.isRunning }

        #expect(engine.processingSettingsCalls.last?.autoHeadroom == true)
    }

    private func settle(timeoutSeconds: Double = 2.0, condition: @escaping () -> Bool) async {
        let start = Date()
        while !condition() && Date().timeIntervalSince(start) < timeoutSeconds {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
