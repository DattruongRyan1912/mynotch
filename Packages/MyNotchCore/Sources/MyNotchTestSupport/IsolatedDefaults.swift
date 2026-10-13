import Foundation

/// A fresh, empty UserDefaults suite per call.
public func makeIsolatedDefaults() -> UserDefaults {
    let suite = "MyNotchTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
