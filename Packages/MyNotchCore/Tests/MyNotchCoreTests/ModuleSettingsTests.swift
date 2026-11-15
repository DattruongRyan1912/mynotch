import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct ModuleSettingsTests {
    @Test func moduleSettingsArePrefixed() {
        let store = SettingsStore(defaults: makeIsolatedDefaults())
        let battery = ModuleSettings(store: store, module: "battery")
        let key = battery.key("lowThreshold", default: 20, clampedTo: 5...50)
        #expect(key.name == "module.battery.lowThreshold")
        battery.set(80, for: key)
        #expect(battery.value(key) == 50)
    }
}
