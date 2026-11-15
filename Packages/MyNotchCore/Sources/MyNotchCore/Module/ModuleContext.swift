import os

/// Everything a module receives from the app. Owned by the registry for one start/stop cycle.
public final class ModuleContext {
    public let id: ModuleID
    public let settings: ModuleSettings
    public let activities: ActivityPublisher
    public let lockScreen: LockScreenPublisher
    public let presenter: ModulePresenter
    public let hotkeys: ModuleHotkeys
    public let services: ModuleServices
    public let permissions: any PermissionCenter
    public let storage: ModuleStorage
    /// Delays for the module; actions still pending are cancelled when the module stops.
    public var scheduler: any Scheduler { moduleScheduler }
    public let logger: Logger

    private let moduleScheduler: ModuleScheduler
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var nextTaskID = 0
    private var isActive = true

    init(
        id: ModuleID,
        settings: ModuleSettings,
        activities: ActivityPublisher,
        lockScreen: LockScreenPublisher,
        presenter: ModulePresenter,
        hotkeys: ModuleHotkeys,
        services: ModuleServices,
        permissions: any PermissionCenter,
        storage: ModuleStorage,
        scheduler: any Scheduler
    ) {
        self.id = id
        self.settings = settings
        self.activities = activities
        self.lockScreen = lockScreen
        self.presenter = presenter
        self.hotkeys = hotkeys
        self.services = services
        self.permissions = permissions
        self.storage = storage
        self.moduleScheduler = ModuleScheduler(base: scheduler)
        self.logger = Log.logger(category: id.rawValue)
    }

    /// Number of `run` tasks that have not finished and were not cancelled (for tests).
    var runningTaskCount: Int { tasks.count }

    /// Runs work that is cancelled automatically when the module stops. Ignored after the module stopped.
    public func run(_ operation: @escaping @MainActor () async -> Void) {
        guard isActive else { return }
        nextTaskID += 1
        let id = nextTaskID
        tasks[id] = Task { [weak self] in
            await operation()
            self?.tasks[id] = nil
        }
    }

    func cancelAll() {
        guard isActive else { return }
        isActive = false
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        moduleScheduler.invalidate()
        activities.invalidate()
        lockScreen.invalidate()
        presenter.invalidate()
        hotkeys.invalidate()
        services.invalidate()
    }
}
