/// Handlers for the app's macOS Services, by service name. The app is the system's services provider and forwards
/// each request here, so modules handle Services without touching AppKit.
public final class ServiceRegistry {
    private struct Registration {
        let owner: ModuleID
        let handler: @MainActor (String) -> Void
    }

    private var registrations: [String: Registration] = [:]

    public init() {}

    /// Replaces any handler already registered under `name`, whichever module owns it.
    public func register(_ name: String, owner: ModuleID, handler: @escaping @MainActor (String) -> Void) {
        registrations[name] = Registration(owner: owner, handler: handler)
    }

    public func unregisterAll(owner: ModuleID) {
        registrations = registrations.filter { $0.value.owner != owner }
    }

    /// Returns false when no running module handles `name`, so the provider can report the request as failed.
    public func handle(name: String, text: String) -> Bool {
        guard let registration = registrations[name] else { return false }
        registration.handler(text)
        return true
    }
}

/// Module-scoped facade over `ServiceRegistry`; the module's services are removed when it stops.
public final class ModuleServices {
    private let registry: ServiceRegistry
    private let module: ModuleID
    private var isActive = true

    init(registry: ServiceRegistry, module: ModuleID) {
        self.registry = registry
        self.module = module
    }

    /// `name` is the one the app's services provider forwards for its `NSServices` entry, e.g. "translate".
    public func register(_ name: String, handler: @escaping @MainActor (String) -> Void) {
        guard isActive else { return }
        registry.register(name, owner: module, handler: handler)
    }

    /// Called by `ModuleContext.cancelAll()` when the module stops; removes the module's services and makes this facade inert.
    func invalidate() {
        guard isActive else { return }
        registry.unregisterAll(owner: module)
        isActive = false
    }
}
