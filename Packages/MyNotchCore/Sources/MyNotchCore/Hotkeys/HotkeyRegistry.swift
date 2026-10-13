import KeyboardShortcuts
import Observation
import SwiftUI

/// All global shortcuts of the app and its modules, backed by KeyboardShortcuts.
@Observable
public final class HotkeyRegistry {
    public struct Registration: Identifiable {
        public let name: KeyboardShortcuts.Name
        public let title: String
        public let owner: ModuleID?
        public var id: String { name.rawValue }
    }

    public private(set) var registrations: [Registration] = []

    public init() {}

    /// Registers a shortcut. `localName` must not contain "." (a KeyboardShortcuts rule).
    public func register(
        _ localName: String,
        title: String,
        owner: ModuleID?,
        initial: KeyboardShortcuts.Shortcut? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        let name = KeyboardShortcuts.Name(Self.qualifiedName(localName, owner: owner), initial: initial)
        unregister(name)
        KeyboardShortcuts.onKeyUp(for: name) { MainActor.assumeIsolated { action() } }
        registrations.append(Registration(name: name, title: title, owner: owner))
    }

    public func unregisterAll(owner: ModuleID) {
        for registration in registrations where registration.owner == owner {
            unregister(registration.name)
        }
    }

    /// Groups of registrations that share the same key combination.
    public func conflicts() -> [[Registration]] {
        let assigned = registrations.compactMap { registration in
            KeyboardShortcuts.getShortcut(for: registration.name).map { ($0, registration) }
        }
        return Dictionary(grouping: assigned, by: \.0)
            .values
            .filter { $0.count > 1 }
            .map { $0.map(\.1) }
    }

    static func qualifiedName(_ localName: String, owner: ModuleID?) -> String {
        precondition(!localName.contains("."), "Shortcut names must not contain '.': \(localName)")
        return "\(owner?.rawValue ?? "app")_\(localName)"
    }

    private func unregister(_ name: KeyboardShortcuts.Name) {
        KeyboardShortcuts.removeHandler(for: name)
        registrations.removeAll { $0.name == name }
    }
}

/// Module-scoped facade over `HotkeyRegistry`; shortcuts are removed when the module stops.
public final class ModuleHotkeys {
    private let registry: HotkeyRegistry
    private let module: ModuleID
    private var isActive = true

    init(registry: HotkeyRegistry, module: ModuleID) {
        self.registry = registry
        self.module = module
    }

    public func register(
        _ localName: String,
        title: String,
        initial: KeyboardShortcuts.Shortcut? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        guard isActive else { return }
        registry.register(localName, title: title, owner: module, initial: initial, action: action)
    }

    /// Called by the registry when the module stops; removes the module's shortcuts and makes this facade inert.
    func invalidate() {
        guard isActive else { return }
        registry.unregisterAll(owner: module)
        isActive = false
    }
}
