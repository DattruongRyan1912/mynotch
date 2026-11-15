/// Reads the permission statuses again every few seconds while something is waiting for a grant and someone can see it.
/// TCC posts no notification when a permission changes, so without this the status-bar dot and the Settings badge only
/// catch up when the app becomes active. It does not poll when nothing is missing or nothing is on screen.
public final class PermissionRefreshLoop {
    private let scheduler: any Scheduler
    private let interval: Duration
    private let shouldRun: () -> Bool
    private let refresh: @MainActor () -> Void
    private var pending: ScheduledAction?

    public var isRunning: Bool { pending != nil }

    /// `shouldRun` is read at every `update()` and every tick; `refresh` reads the statuses.
    public init(
        scheduler: any Scheduler, interval: Duration = .seconds(3),
        shouldRun: @escaping () -> Bool, refresh: @escaping @MainActor () -> Void
    ) {
        self.scheduler = scheduler
        self.interval = interval
        self.shouldRun = shouldRun
        self.refresh = refresh
    }

    /// Something `shouldRun` depends on may have changed. Starting refreshes at once, so a notch or window that was just
    /// opened is never a few seconds behind; stopping cancels the timer.
    public func update() {
        if shouldRun() {
            guard pending == nil else { return }
            refreshAndContinue()
        } else {
            stop()
        }
    }

    /// The loop is wanted while a permission of an enabled module is optional and not granted, and the Settings window or
    /// the notch is open. Required permissions are polled by the registry for the modules that wait on them.
    public static func isWanted(missingOptional: Int, settingsVisible: Bool, notchOpen: Bool) -> Bool {
        missingOptional > 0 && (settingsVisible || notchOpen)
    }

    /// The next tick is scheduled before refreshing, so a `refresh` that asks `update()` again finds the timer running.
    private func refreshAndContinue() {
        pending = scheduler.schedule(after: interval) { [weak self] in self?.tick() }
        refresh()
        if !shouldRun() { stop() }
    }

    private func tick() {
        pending = nil
        guard shouldRun() else { return }
        refreshAndContinue()
    }

    private func stop() {
        pending?.cancel()
        pending = nil
    }
}

/// Spots the user coming back to MyNotch from System Settings, where a permission is granted, as
/// `NSWorkspace.didActivateApplicationNotification` reports one activation after another.
public final class SystemSettingsReturn {
    public static let systemSettingsBundleID = "com.apple.systempreferences"

    private let ownBundleID: String
    private var wasInSystemSettings = false

    public init(ownBundleID: String) {
        self.ownBundleID = ownBundleID
    }

    /// The app that just came to the front. True once for each return from System Settings to MyNotch.
    public func activated(_ bundleID: String?) -> Bool {
        let returned = wasInSystemSettings && bundleID == ownBundleID
        wasInSystemSettings = bundleID == Self.systemSettingsBundleID
        return returned
    }
}
