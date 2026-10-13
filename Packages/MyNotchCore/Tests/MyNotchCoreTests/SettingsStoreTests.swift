import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@Suite struct SettingsStoreTests {
    @Test func returnsDefaultUntilSet() {
        let store = SettingsStore(defaults: makeIsolatedDefaults())
        let key = SettingKey("interface.openDelayMs", default: 150)
        #expect(store.value(key) == 150)
        store.set(400, for: key)
        #expect(store.value(key) == 400)
        store.reset(key)
        #expect(store.value(key) == 150)
    }

    @Test func clampsOutOfRangeValues() {
        let store = SettingsStore(defaults: makeIsolatedDefaults())
        let key = SettingKey("interface.closeDelayMs", default: 300, clampedTo: 0...1000)
        store.set(5_000, for: key)
        #expect(store.value(key) == 1000)
    }

    @Test func roundTripsCodableValues() {
        let store = SettingsStore(defaults: makeIsolatedDefaults())
        let key = SettingKey<[String]>("app.recent", default: [])
        store.set(["a", "b"], for: key)
        #expect(store.value(key) == ["a", "b"])
    }
}
