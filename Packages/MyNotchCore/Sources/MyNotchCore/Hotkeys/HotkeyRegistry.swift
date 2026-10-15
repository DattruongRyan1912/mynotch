import KeyboardShortcuts
import Observation
import SwiftUI
import os

/// All global shortcuts of the app and its modules. The backend is KeyboardShortcuts in the app and a fake in tests.
@Observable
public final class HotkeyRegistry {
    public struct Registration: Identifiable {
        public let name: KeyboardShortcuts.Name
        public let title: String
        public let owner: ModuleID?
        /// The combination it was registered with, before the user changed anything; nil when it has none.
        public let defaultShortcut: KeyboardShortcuts.Shortcut?
        public var id: String { name.rawValue }

        init(name: KeyboardShortcuts.Name, title: String, owner: ModuleID?, defaultShortcut: KeyboardShortcuts.Shortcut? = nil) {
            self.name = name
            self.title = title
            self.owner = owner
            self.defaultShortcut = defaultShortcut
        }
    }

    public private(set) var registrations: [Registration] = []
    @ObservationIgnored private let backend: any HotkeyBackend
    @ObservationIgnored private let onDefaultCollision: ((_ new: Registration, _ existing: Registration) -> Void)?

    /// `onDefaultCollision` hears of a registration whose default is already another one's. A collision is a bug in
    /// whoever registers (two handlers on one key press), not something the user did, so without one it is logged and,
    /// in a debug build, stops the app where the second one registers. Tests that provoke one pass their own.
    public init(
        backend: any HotkeyBackend,
        onDefaultCollision: ((_ new: Registration, _ existing: Registration) -> Void)? = nil
    ) {
        self.backend = backend
        self.onDefaultCollision = onDefaultCollision
    }

    /// Registers a shortcut. `localName` must not contain "." (a KeyboardShortcuts rule).
    public func register(
        _ localName: String,
        title: String,
        owner: ModuleID?,
        initial: KeyboardShortcuts.Shortcut? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        let name = backend.makeName(Self.qualifiedName(localName, owner: owner), initial: initial)
        unregister(name)
        let registration = Registration(name: name, title: title, owner: owner, defaultShortcut: initial)
        // Every module and the app register through here, so this is the one place that sees all the defaults.
        if let initial, let existing = registrations.first(where: { $0.defaultShortcut == initial }) {
            (onDefaultCollision ?? Self.reportDefaultCollision)(registration, existing)
        }
        backend.onKeyUp(for: name, action: action)
        registrations.append(registration)
    }

    /// Removes one shortcut: its handler goes and its row disappears from the registry. Nothing happens for a name
    /// that is not registered. The key combination the user recorded stays stored, so registering again restores it.
    public func unregister(_ localName: String, owner: ModuleID?) {
        let qualified = Self.qualifiedName(localName, owner: owner)
        for registration in registrations where registration.name.rawValue == qualified {
            unregister(registration.name)
        }
    }

    public func unregisterAll(owner: ModuleID) {
        for registration in registrations where registration.owner == owner {
            unregister(registration.name)
        }
    }

    /// Groups of registrations that share the same key combination.
    public func conflicts() -> [[Registration]] {
        let assigned = registrations.compactMap { registration in
            backend.getShortcut(for: registration.name).map { ($0, registration) }
        }
        return Dictionary(grouping: assigned, by: \.0)
            .values
            .filter { $0.count > 1 }
            .map { $0.map(\.1).sorted { $0.id < $1.id } }
            .sorted { $0[0].id < $1[0].id }
    }

    /// The default reaction: a fault in the log, and in a debug build a stop, so a collision is found when the app starts
    /// instead of when a user presses the key. Names only; titles and shortcuts are not user content but are not needed.
    static func reportDefaultCollision(_ new: Registration, _ existing: Registration) {
        let message = "Shortcuts \(new.id) and \(existing.id) have the same default key combination"
        Log.logger(category: "hotkeys").fault("\(message, privacy: .public)")
        assertionFailure(message)
    }

    static func qualifiedName(_ localName: String, owner: ModuleID?) -> String {
        precondition(!localName.contains("."), "Shortcut names must not contain '.': \(localName)")
        return "\(owner?.rawValue ?? "app")_\(localName)"
    }

    private func unregister(_ name: KeyboardShortcuts.Name) {
        backend.removeHandler(for: name)
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

    /// Removes one of this module's shortcuts, e.g. for something the user took away. No-op once the module stopped.
    public func unregister(_ localName: String) {
        guard isActive else { return }
        registry.unregister(localName, owner: module)
    }

    /// Called by `ModuleContext.cancelAll()` when the module stops; removes the module's shortcuts and makes this facade inert.
    func invalidate() {
        guard isActive else { return }
        registry.unregisterAll(owner: module)
        isActive = false
    }
}
