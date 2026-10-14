import Observation
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct TabOrderTests {
    @Test func noStoredOrderKeepsTheModuleOrder() {
        #expect(TabOrder.merged(stored: [], available: ["a", "b", "c"]) == ["a", "b", "c"])
    }

    @Test func theStoredOrderWins() {
        #expect(TabOrder.merged(stored: ["c", "a", "b"], available: ["a", "b", "c"]) == ["c", "a", "b"])
    }

    @Test func aModuleWithoutAStoredPositionGoesLastInModuleOrder() {
        #expect(TabOrder.merged(stored: ["c", "a"], available: ["a", "b", "c", "d"]) == ["c", "a", "b", "d"])
    }

    @Test func aStoredModuleThatIsNotThereIsSkipped() {
        #expect(TabOrder.merged(stored: ["gone", "c", "a"], available: ["a", "b", "c"]) == ["c", "a", "b"])
    }

    @Test func aRepeatedIdCountsOnce() {
        #expect(TabOrder.merged(stored: ["b", "a", "b"], available: ["a", "b"]) == ["b", "a"])
    }

    @Test func nothingAvailableIsNothing() {
        #expect(TabOrder.merged(stored: ["a"], available: []).isEmpty)
    }

    @Test func savingTheVisibleOrderKeepsWhatIsSwitchedOffAfterIt() {
        #expect(TabOrder.updated(stored: ["a", "off", "b"], visible: ["b", "a"]) == ["b", "a", "off"])
        #expect(TabOrder.updated(stored: [], visible: ["b", "a"]) == ["b", "a"])
    }

    @Test func aModuleSwitchedBackOnJoinsAfterTheOnesThatWereVisible() {
        let stored = TabOrder.updated(stored: ["a", "off", "b"], visible: ["b", "a"])
        #expect(TabOrder.merged(stored: stored, available: ["a", "off", "b"]) == ["b", "a", "off"])
    }
}

@Suite struct RegistryTabOrderTests {
    func make() async -> RegistryHarness {
        let harness = Harness([FakeModule("a", order: 1), FakeModule("b", order: 2), FakeModule("c", order: 3)])
        await harness.registry.bootstrap()
        return harness
    }

    @Test func withoutAStoredOrderTheTabsFollowTheModules() async {
        let harness = await make()
        #expect(harness.registry.tabs.map(\.id) == ["a", "b", "c"])
    }

    @Test func theStoredOrderArrangesTheTabs() async {
        let harness = await make()
        harness.settings.set(["c", "a"], for: ModuleRegistry.tabOrderKey)
        #expect(harness.registry.tabs.map(\.id) == ["c", "a", "b"])
    }

    @Test func resettingTheOrderGoesBackToTheModuleOrder() async {
        let harness = await make()
        harness.settings.set(["c", "b", "a"], for: ModuleRegistry.tabOrderKey)
        harness.settings.reset(ModuleRegistry.tabOrderKey)
        #expect(harness.registry.tabs.map(\.id) == ["a", "b", "c"])
    }

    @Test func aStoppedModuleLeavesAndComesBackToItsPlace() async {
        let harness = await make()
        harness.settings.set(["c", "b", "a"], for: ModuleRegistry.tabOrderKey)
        await harness.registry.setEnabled(false, for: "b")
        #expect(harness.registry.tabs.map(\.id) == ["c", "a"])
        await harness.registry.setEnabled(true, for: "b")
        #expect(harness.registry.tabs.map(\.id) == ["c", "b", "a"])
    }

    @Test func aModuleThatIsNotInTheStoredOrderGoesLast() async {
        let harness = await make()
        harness.settings.set(["b", "a"], for: ModuleRegistry.tabOrderKey)
        #expect(harness.registry.tabs.map(\.id) == ["b", "a", "c"])
    }

    @Test func changingTheOrderNotifiesWhoReadsTheTabs() async {
        let harness = await make()
        nonisolated(unsafe) var changes = 0
        withObservationTracking { _ = harness.registry.tabs } onChange: { changes += 1 }
        harness.settings.set(["c"], for: ModuleRegistry.tabOrderKey)
        #expect(changes == 1)
    }
}
