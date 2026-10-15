import AppKit
import MyNotchCore
import NotchUI
import Observation
import SwiftUI

/// Setting names and defaults in one place, shared by the running module and the Settings rows.
struct LockScreenKeys {
    let showMedia: SettingKey<Bool>
    let showTimer: SettingKey<Bool>
    let showBattery: SettingKey<Bool>
    /// The media view draws its buttons, and the panel takes clicks for them. Off, the track and its progress are shown and
    /// nothing can be pressed.
    let showMediaControls: SettingKey<Bool>
    /// The media view shows the line being sung and the next one under the track. Apart from the controls: a view can have
    /// either, both or neither.
    let showLyrics: SettingKey<Bool>

    init(_ settings: ModuleSettings) {
        showMedia = settings.key("showMedia", default: true)
        showTimer = settings.key("showTimer", default: true)
        showBattery = settings.key("showBattery", default: false)
        showMediaControls = settings.key("showMediaControls", default: true)
        showLyrics = settings.key("showLyrics", default: true)
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

    /// Called once, on the first `start`, so SkyLight is not loaded while the module is off.
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
    /// Whether the lock screen can be seen right now, set before anything is shown or hidden so that the views stop at once.
    private let presence = LockScreenPresence()
    /// Keeps the panel's click-through state in step with what is shown and the controls setting, while the panel is up.
    private var clickWatch: Task<Void, Never>?

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
        // Kept across stops: the SkyLight space belongs to the shim, so a new shim would make another one every time.
        let shim = self.shim ?? makeShim()
        self.shim = shim
        guard shim.isAvailable else { throw .unavailable(reason: Self.unavailableReason) }
        self.context = context
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
        presence.set(false)
        hide()
        context = nil
    }

    public func makeTab() -> NotchTab? { nil }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        AnyView(LockScreenSettingsView(settings: environment.settings, keys: LockScreenKeys(environment.settings)))
    }

    private func stateChanged(_ state: LockStateObserver.State) {
        pendingHide?.cancel()
        pendingHide = nil
        // At once, not after the hide delay: a display that sleeps must stop the lyric lines' timeline and sweep now.
        presence.set(state.isLockScreenVisible)
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
        let root = LockScreenRootView(
            lockScreen: context.lockScreen, isAllowed: isAllowed, presence: presence,
            controlsEnabled: { settings.value(keys.showMediaControls) }, lyricsEnabled: { settings.value(keys.showLyrics) }
        )
        guard context.lockScreen.current(allowing: isAllowed) != nil, let window = makeWindow(AnyView(root)) else { return }
        self.window = window
        window.takesClicks = takesClicks()
        watchClicks(of: window)
        shim.makeLockScreenSpace()
        window.show()
        shim.attach(windowNumber: window.windowNumber)
    }

    /// Clicks reach the panel only while the view shown has buttons and the user lets them show. Anything else, and the panel is
    /// click-through, so it cannot swallow a click it has no button for.
    private func takesClicks() -> Bool {
        guard let context else { return false }
        let settings = context.settings
        let keys = LockScreenKeys(settings)
        let entry = context.lockScreen.current(allowing: { keys.allows($0, in: settings) })
        return entry?.isInteractive == true && settings.value(keys.showMediaControls)
    }

    private func watchClicks(of window: any LockScreenWindow) {
        clickWatch?.cancel()
        clickWatch = Task { [weak self, weak window] in
            for await takesClicks in Observations({ self?.takesClicks() ?? false }) {
                guard let window else { return }
                window.takesClicks = takesClicks
            }
        }
    }

    private func hide() {
        pendingHide = nil
        clickWatch?.cancel()
        clickWatch = nil
        guard let window else { return }
        self.window = nil
        shim?.detach(windowNumber: window.windowNumber)
        window.dismiss()
    }
}
