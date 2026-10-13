import os

/// Everything a module receives from the app. Owned by the registry for one start/stop cycle.
public final class ModuleContext {
    public let id: ModuleID
    public let settings: ModuleSettings
    public let activities: ActivityPublisher
    public let presenter: any NotchPresenter
    public let hotkeys: ModuleHotkeys
    public let permissions: any PermissionCenter
    public let logger: Logger

    private var tasks: [Task<Void, Never>] = []

    init(
        id: ModuleID,
        settings: ModuleSettings,
        activities: ActivityPublisher,
        presenter: any NotchPresenter,
        hotkeys: ModuleHotkeys,
        permissions: any PermissionCenter
    ) {
        self.id = id
        self.settings = settings
        self.activities = activities
        self.presenter = presenter
        self.hotkeys = hotkeys
        self.permissions = permissions
        self.logger = Log.logger(category: id.rawValue)
    }

    /// Runs work that is cancelled automatically when the module stops.
    public func run(_ operation: @escaping @MainActor () async -> Void) {
        tasks.append(Task { await operation() })
    }

    func cancelAll() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        activities.invalidate()
        hotkeys.invalidate()
    }
}
