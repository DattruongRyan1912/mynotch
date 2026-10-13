import Foundation
import Observation
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

    @Test func writesNotifyOnlyReadersOfThatKey() {
        let store = SettingsStore(defaults: makeIsolatedDefaults())
        let watched = SettingKey("app.watched", default: 1)
        let other = SettingKey("app.other", default: 1)
        // onChange is @Sendable but runs synchronously on the writing (main) thread in these tests.
        nonisolated(unsafe) var notifications = 0
        func observe() {
            withObservationTracking { _ = store.value(watched) } onChange: { notifications += 1 }
        }
        observe()
        store.set(5, for: other)
        #expect(notifications == 0)
        store.set(1, for: watched)          // equal to the default but not stored yet: a real write
        #expect(notifications == 1)
        observe()
        store.set(1, for: watched)          // same bytes again: no-op
        #expect(notifications == 1)
        store.reset(watched)
        #expect(notifications == 2)
    }

    @Test func clampsStoredValuesOnReadAndFallsBackOnCorruptData() {
        let defaults = makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        let key = SettingKey("interface.delay", default: 300, clampedTo: 0...1000)
        defaults.set(Data("-5".utf8), forKey: key.name)
        #expect(store.value(key) == 0)
        defaults.set(Data("not json".utf8), forKey: key.name)
        #expect(store.value(key) == 300)
        let outOfRangeDefault = SettingKey("interface.big", default: 5000, clampedTo: 0...1000)
        #expect(store.value(outOfRangeDefault) == 1000)
    }
}
