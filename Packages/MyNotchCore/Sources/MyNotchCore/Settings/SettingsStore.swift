import Foundation
import Observation
import SwiftUI

/// JSON-encoded settings on top of `UserDefaults`, observable by SwiftUI.
///
/// Assumes it is the only writer of its keys and that the app shares a single instance:
/// external writes (e.g. `defaults write`) are not observed until the next in-app write.
/// Custom `Value` types must be `nonisolated` so their `Codable` conformance is usable here.
@Observable
public final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults
    /// One observable counter per key, so a write only refreshes readers of that key.
    @ObservationIgnored private var revisions: [String: Revision] = [:]
    /// Sorted keys make equal values encode to equal bytes, so no-op writes can be skipped.
    @ObservationIgnored private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func value<Value>(_ key: SettingKey<Value>) -> Value {
        _ = revision(for: key.name).count
        guard let data = defaults.data(forKey: key.name),
              let decoded = try? JSONDecoder().decode(Value.self, from: data) else {
            return key.normalize(key.defaultValue)
        }
        return key.normalize(decoded)
    }

    public func set<Value>(_ value: Value, for key: SettingKey<Value>) {
        guard let data = try? encoder.encode(key.normalize(value)) else {
            assertionFailure("Setting \(key.name) could not be encoded")
            return
        }
        guard data != defaults.data(forKey: key.name) else { return }
        defaults.set(data, forKey: key.name)
        revision(for: key.name).count += 1
    }

    public func setRawJSONData(_ data: Data, forKey name: String) {
        guard data != defaults.data(forKey: name) else { return }
        defaults.set(data, forKey: name)
        revision(for: name).count += 1
    }

    public func rawJSONData(forKey name: String) -> Data? {
        _ = revision(for: name).count
        return defaults.data(forKey: name)
    }

    public func storedRawSettings() -> [String: Data] {
        var result: [String: Data] = [:]
        let dict = defaults.dictionaryRepresentation()
        for (key, value) in dict {
            guard let data = value as? Data else { continue }
            if key == "app.permissionIdentity" { continue }
            if key.hasPrefix("app.") || key.hasPrefix("interface.") || key.hasPrefix("module.") {
                result[key] = data
            }
        }
        return result
    }

    public func reset<Value>(_ key: SettingKey<Value>) {
        guard defaults.object(forKey: key.name) != nil else { return }
        defaults.removeObject(forKey: key.name)
        revision(for: key.name).count += 1
    }

    public func binding<Value>(_ key: SettingKey<Value>) -> Binding<Value> {
        Binding(get: { self.value(key) }, set: { self.set($0, for: key) })
    }

    private func revision(for name: String) -> Revision {
        if let existing = revisions[name] { return existing }
        let created = Revision()
        revisions[name] = created
        return created
    }
}

@Observable
private final class Revision {
    var count = 0
}
