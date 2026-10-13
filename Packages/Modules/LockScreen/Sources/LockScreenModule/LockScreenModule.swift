import AppKit
import MyNotchCore
import NotchUI
import SwiftUI

/// Setting names and defaults in one place, shared by the running module and the Settings rows.
struct LockScreenKeys {
    let showMedia: SettingKey<Bool>
    let showTimer: SettingKey<Bool>
    let showBattery: SettingKey<Bool>

    init(_ settings: ModuleSettings) {
        showMedia = settings.key("showMedia", default: true)
        showTimer = settings.key("showTimer", default: true)
        showBattery = settings.key("showBattery", default: false)
    }

    /// Whether the user wants `module`'s view on the lock screen. A module with no switch here is never shown.
    func allows(_ module: ModuleID, in settings: ModuleSettings) -> Bool {
        switch module {
        case "media": settings.value(showMedia)
        case "timer": settings.value(showTimer)
        case "battery": settings.value(showBattery)
        default: false
        }
    }
}

/// Experimental: shows what Media, Timer and Battery offer (`context.lockScreen`) on the lock screen. macOS has no
/// public way to draw there, so a private SkyLight space does it, and macOS updates can break it.
public final class LockScreenModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "lockscreen",
        displayName: "Màn hình khoá",
        systemImage: "lock.display",
        defaultEnabled: false,
        order: 990
    )

    static let unavailableReason = "macOS này không có hàm SkyLight cần thiết"
    /// Keeps the widget up for the moment the lock screen fades, so it doesn't vanish a beat before it.
    static let hideDelay = Duration.milliseconds(300)

    /// Made in `start`, so SkyLight is not loaded while the module is off.
    private let makeShim: () -> any SkyLightShim
    private let makeWindow: (AnyView) -> (any LockScreenWindow)?
    private let distributedCenter: NotificationCenter
    private let workspaceCenter: NotificationCenter
    private let isScreenLocked: () -> Bool
    private var context: ModuleContext?
    private var shim: (any SkyLightShim)?
    private var observer: LockStateObserver?
    private var window: (any LockScreenWindow)?
    private var pendingHide: ScheduledAction?

    public convenience init() {
        self.init(
            makeShim: { SystemSkyLightShim() },
            makeWindow: LockScreenPanel.make(content:),
            distributedCenter: DistributedNotificationCenter.default(),
            workspaceCenter: NSWorkspace.shared.notificationCenter,
            isScreenLocked: LockStateObserver.isSessionScreenLocked
        )
    }

    /// Tests pass fakes for everything that would reach the system: SkyLight, windows, notifications and the session.
    init(
        makeShim: @escaping () -> any SkyLightShim,
        makeWindow: @escaping (AnyView) -> (any LockScreenWindow)?,
        distributedCenter: NotificationCenter,
        workspaceCenter: NotificationCenter,
        isScreenLocked: @escaping () -> Bool
    ) {
        self.makeShim = makeShim
        self.makeWindow = makeWindow
        self.distributedCenter = distributedCenter
        self.workspaceCenter = workspaceCenter
        self.isScreenLocked = isScreenLocked
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        let shim = makeShim()
        guard shim.isAvailable else { throw .unavailable(reason: Self.unavailableReason) }
        self.context = context
        self.shim = shim
        let observer = LockStateObserver(distributed: distributedCenter, workspace: workspaceCenter, isScreenLocked: isScreenLocked)
        self.observer = observer
        observer.start { [weak self] state in self?.stateChanged(state) }
        stateChanged(observer.state)
    }

    public func stop() async {
        pendingHide?.cancel()
        pendingHide = nil
        observer?.stop()
        observer = nil
        hide()
        shim = nil
        context = nil
    }

    public func makeTab() -> NotchTab? { nil }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        AnyView(LockScreenSettingsView(settings: environment.settings, keys: LockScreenKeys(environment.settings)))
    }

    private func stateChanged(_ state: LockStateObserver.State) {
        pendingHide?.cancel()
        pendingHide = nil
        if state.isLockScreenVisible {
            show()
        } else if window != nil {
            pendingHide = context?.scheduler.schedule(after: Self.hideDelay) { [weak self] in self?.hide() }
        }
    }

    /// Builds the panel only when there is something to show, and makes the SkyLight space only then, so nothing
    /// private is touched until a lock screen actually has content.
    private func show() {
        guard window == nil, let context, let shim else { return }
        let settings = context.settings
        let keys = LockScreenKeys(settings)
        let isAllowed: (ModuleID) -> Bool = { keys.allows($0, in: settings) }
        guard context.lockScreen.current(allowing: isAllowed) != nil,
              let window = makeWindow(AnyView(LockScreenRootView(lockScreen: context.lockScreen, isAllowed: isAllowed))) else { return }
        self.window = window
        shim.makeLockScreenSpace()
        window.show()
        shim.attach(windowNumber: window.windowNumber)
    }

    private func hide() {
        pendingHide = nil
        guard let window else { return }
        self.window = nil
        shim?.detach(windowNumber: window.windowNumber)
        window.dismiss()
    }
}
