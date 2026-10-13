import Foundation
import Observation
import SwiftUI

/// JSON-encoded settings on top of `UserDefaults`, observable by SwiftUI.
@Observable
public final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults
    /// Bumped on every write so views reading any setting refresh.
    private var revision = 0

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func value<Value>(_ key: SettingKey<Value>) -> Value {
        _ = revision
        guard let data = defaults.data(forKey: key.name),
              let decoded = try? JSONDecoder().decode(Value.self, from: data) else {
            return key.defaultValue
        }
        return key.normalize(decoded)
    }

    public func set<Value>(_ value: Value, for key: SettingKey<Value>) {
        guard let data = try? JSONEncoder().encode(key.normalize(value)) else { return }
        defaults.set(data, forKey: key.name)
        revision += 1
    }

    public func reset<Value>(_ key: SettingKey<Value>) {
        defaults.removeObject(forKey: key.name)
        revision += 1
    }

    public func binding<Value>(_ key: SettingKey<Value>) -> Binding<Value> {
        Binding(get: { self.value(key) }, set: { self.set($0, for: key) })
    }
}
