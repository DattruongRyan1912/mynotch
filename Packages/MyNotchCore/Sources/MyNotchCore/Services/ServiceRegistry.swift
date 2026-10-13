/// Handlers for the app's macOS Services, by service name. The app is the system's services provider and forwards
/// each request here, so modules handle Services without touching AppKit.
///
/// A request can arrive before its module runs: choosing a service launches MyNotch, and the system sends the request
/// while the modules are still starting. So the latest unhandled request per name waits up to `pendingLifetime` for
/// a handler.
public final class ServiceRegistry {
    /// Long enough for launch and a module start, short enough that a request the user gave up on doesn't pop up later.
    static let pendingLifetime: Duration = .seconds(10)

    private struct Registration {
        let owner: ModuleID
        let handler: @MainActor (String) -> Void
    }

    private struct PendingRequest {
        let id: Int
        let text: String
        let expiry: ScheduledAction
    }

    private let scheduler: any Scheduler
    private var registrations: [String: Registration] = [:]
    private var pending: [String: PendingRequest] = [:]
    private var nextRequestID = 0

    public init(scheduler: any Scheduler) {
        self.scheduler = scheduler
    }

    /// Replaces any handler already registered under `name`, whichever module owns it. A request waiting for `name`
    /// is delivered on the scheduler's next turn, not from inside this call: a module registers from `start`, and its
    /// tab only exists once `start` has returned.
    public func register(_ name: String, owner: ModuleID, handler: @escaping @MainActor (String) -> Void) {
        registrations[name] = Registration(owner: owner, handler: handler)
        guard pending[name] != nil else { return }
        scheduler.schedule(after: .zero) { [weak self] in self?.deliverPending(name) }
    }

    public func unregisterAll(owner: ModuleID) {
        registrations = registrations.filter { $0.value.owner != owner }
    }

    /// Hands `text` to the handler of `name`, or keeps it for the next handler registered within `pendingLifetime`,
    /// replacing any request already waiting. Both count as handled, so this returns true and the Services menu shows
    /// no error while a module is still starting; a request no handler claims in time is dropped silently.
    public func handle(name: String, text: String) -> Bool {
        if let registration = registrations[name] {
            pending.removeValue(forKey: name)?.expiry.cancel()
            registration.handler(text)
        } else {
            queue(text, for: name)
        }
        return true
    }

    private func queue(_ text: String, for name: String) {
        pending.removeValue(forKey: name)?.expiry.cancel()
        nextRequestID += 1
        let id = nextRequestID
        // Checks the id too, so a stale expiry that fires anyway cannot drop the newer request.
        let expiry = scheduler.schedule(after: Self.pendingLifetime) { [weak self] in
            guard let self, self.pending[name]?.id == id else { return }
            self.pending[name] = nil
        }
        pending[name] = PendingRequest(id: id, text: text, expiry: expiry)
    }

    /// Keeps the request when its handler went away before this turn, e.g. a module whose start failed after registering.
    private func deliverPending(_ name: String) {
        guard let registration = registrations[name], let request = pending.removeValue(forKey: name) else { return }
        request.expiry.cancel()
        registration.handler(request.text)
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
