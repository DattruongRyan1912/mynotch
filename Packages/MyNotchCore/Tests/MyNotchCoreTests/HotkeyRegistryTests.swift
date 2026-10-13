import Testing
@testable import MyNotchCore

@Suite struct HotkeyRegistryTests {
    @Test func namesAreScopedByOwner() {
        #expect(HotkeyRegistry.qualifiedName("toggleNotch", owner: nil) == "app_toggleNotch")
        #expect(HotkeyRegistry.qualifiedName("openTab", owner: "battery") == "battery_openTab")
    }

    @Test func invalidatedModuleHotkeysUnregisterAndIgnoreLateRegistrations() {
        let registry = HotkeyRegistry()
        let hotkeys = ModuleHotkeys(registry: registry, module: "battery")
        hotkeys.register("openTab", title: "Open") {}
        #expect(registry.registrations.map(\.id) == ["battery_openTab"])
        hotkeys.invalidate()
        #expect(registry.registrations.isEmpty)
        hotkeys.register("late", title: "Late") {}
        #expect(registry.registrations.isEmpty)
    }
}
