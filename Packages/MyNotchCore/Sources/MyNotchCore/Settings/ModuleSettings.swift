import SwiftUI

/// Settings access confined to the `module.<id>.` namespace.
public struct ModuleSettings {
    private let store: SettingsStore
    private let module: ModuleID

    init(store: SettingsStore, module: ModuleID) {
        self.store = store
        self.module = module
    }

    public func key<Value>(_ name: String, default defaultValue: Value) -> SettingKey<Value> {
        precondition(name != "enabled", "\"enabled\" is reserved for ModuleRegistry")
        return SettingKey(Self.qualifiedName(name, module: module), default: defaultValue)
    }

    public func key<Value: Comparable>(_ name: String, default defaultValue: Value, clampedTo range: ClosedRange<Value>) -> SettingKey<Value> {
        precondition(name != "enabled", "\"enabled\" is reserved for ModuleRegistry")
        return SettingKey(Self.qualifiedName(name, module: module), default: defaultValue, clampedTo: range)
    }

    public func value<Value>(_ key: SettingKey<Value>) -> Value { store.value(checked(key)) }
    public func set<Value>(_ value: Value, for key: SettingKey<Value>) { store.set(value, for: checked(key)) }
    public func binding<Value>(_ key: SettingKey<Value>) -> Binding<Value> { store.binding(checked(key)) }

    static func qualifiedName(_ name: String, module: ModuleID) -> String {
        "module.\(module.rawValue).\(name)"
    }

    private func checked<Value>(_ key: SettingKey<Value>) -> SettingKey<Value> {
        precondition(key.name.hasPrefix("module.\(module.rawValue)."), "Key \(key.name) is outside module \(module)")
        return key
    }
}
