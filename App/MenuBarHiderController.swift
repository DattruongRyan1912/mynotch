import AppKit
import MyNotchCore

/// The separator status item ‹ and what drives it: the settings, a click on it and the pointer on the menu bar. The rules
/// (lengths, timers, what is refused) are `MenuBarHider`'s; this only owns the real item and the event monitors.
final class MenuBarHiderController {
    /// Nothing collapses by itself for this long after the user turns the hider on: they are placing icons.
    private static let arrangingGrace: Duration = .seconds(60)

    private let settings: SettingsStore
    private let hider: MenuBarHider
    private let notice: MenuBarNotice
    /// The MyNotch icon, which toggles; the separator is created after it, so the system lays it out on its left.
    private var toggleItem: NSStatusItem?
    private var separatorItem: NSStatusItem?
    private var separator: StatusItemSeparator?
    private let hover = MenuBarHoverMonitor()
    /// Whether the setting was on at the last look, so only a switch-on gets the arranging grace, not a launch.
    private var wasEnabled: Bool
    /// ⌘-dragging "‹" off the menu bar clears its `isVisible`, which is mirrored into the setting.
    private var visibilityObservation: NSKeyValueObservation?
    private var layoutObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init(settings: SettingsStore, scheduler: any Scheduler, notice: MenuBarNotice) {
        self.settings = settings
        self.notice = notice
        wasEnabled = settings.value(MenuBarHiderSettings.enabled)
        hider = MenuBarHider(settings: settings, scheduler: scheduler)
        hover.onChange = { [weak self] inside in self?.hider.pointerMoved(inMenuBar: inside) }
        hider.onForcedExpand = { [weak self] in
            self?.notice.show("Biểu tượng MyNotch bị che nên các icon đã ẩn được hiện lại.")
        }
        observeSettings()
        observeQuitting()
    }

    /// Whether the user switched the hider on. The separator exists only while the MyNotch icon does too, since that icon is
    /// how the hidden ones come back.
    var isEnabled: Bool { settings.value(MenuBarHiderSettings.enabled) }

    /// The MyNotch icon appeared or went away.
    func setToggleItem(_ item: NSStatusItem?) {
        toggleItem = item
        sync()
    }

    /// A click on the MyNotch icon or the shortcut. A refused collapse (the separator is not left of the icon) says what to
    /// do, on the notch and to VoiceOver, instead of leaving a dead icon.
    func toggle() {
        guard separatorItem != nil else { return }
        if !hider.toggle() {
            Log.logger(category: "app").notice("Menu-bar hider: not collapsing, the separator is not left of the MyNotch icon")
            NSSound.beep()
            notice.show("Kéo dấu ‹ sang trái biểu tượng MyNotch (giữ ⌘)")
        }
    }

    var isCollapsed: Bool { hider.isCollapsed }

    /// Shows everything again, for the moments the app is going away and the icons must not stay hidden.
    func expandNow() { hider.expand() }

    private func observeSettings() {
        Task { [weak self, settings] in
            for await _ in Observations({
                (settings.value(MenuBarHiderSettings.enabled), settings.value(MenuBarHiderSettings.autoCollapseSeconds),
                 settings.value(MenuBarHiderSettings.revealOnHover))
            }) {
                self?.sync()
                self?.hider.settingsChanged()
            }
        }
    }

    /// Whatever the way out is (quitting, shutting down), the icons come back first: the status item's length is never
    /// saved, but the wait for the modules to stop can last seconds.
    private func observeQuitting() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hider.expand() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hider.expand() }
        }
    }

    private func sync() {
        let enabled = isEnabled
        let justEnabled = enabled && !wasEnabled
        wasEnabled = enabled
        let wanted = enabled && toggleItem != nil
        if wanted, separatorItem == nil {
            addSeparator(quietFor: justEnabled ? Self.arrangingGrace : .zero)
        } else if !wanted, separatorItem != nil {
            removeSeparator()
        }
        hover.setRunning(wanted && settings.value(MenuBarHiderSettings.revealOnHover))
    }

    private func addSeparator(quietFor grace: Duration) {
        guard let toggleItem else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // A fixed name, so macOS keeps where the user dragged it across launches whatever order the items are made in.
        item.autosaveName = "MyNotchSeparator"
        // The name also keeps whether the item is shown, and a ⌘-drag off the bar stored "hidden" under it. The user's settings
        // say it should exist now, so it does.
        item.isVisible = true
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "chevron.compact.left", accessibilityDescription: "Dấu ngăn icon menu bar")
            if button.image == nil { button.title = "‹" }
            button.toolTip = "Giữ ⌘ và kéo icon của app khác sang bên trái dấu này để ẩn chúng."
            button.target = self
            button.action = #selector(separatorClicked)
        }
        let separator = StatusItemSeparator(item: item, toggle: toggleItem)
        separatorItem = item
        self.separator = separator
        // After the name and visibility are settled, so only the user's own removal is heard.
        visibilityObservation = item.observe(\.isVisible, options: [.new]) { [weak self] _, change in
            guard change.newValue == false else { return }
            Task { @MainActor in self?.separatorWasRemoved() }
        }
        observeLayout(of: item, and: toggleItem)
        hider.attach(separator, quietFor: grace)
    }

    private func removeSeparator() {
        visibilityObservation = nil
        stopObservingLayout()
        hider.detach()
        if let separatorItem { NSStatusBar.system.removeStatusItem(separatorItem) }
        separatorItem = nil
        separator = nil
    }

    /// The user dragged "‹" off the menu bar: with nothing to hide behind, the hider is off, and the user is told.
    private func separatorWasRemoved() {
        guard separatorItem != nil else { return }
        Log.logger(category: "app").notice("Menu-bar hider: the separator was removed from the menu bar, switching the hider off")
        settings.set(false, for: MenuBarHiderSettings.enabled)
        notice.show("Dấu ‹ đã bị gỡ khỏi menu bar nên tính năng ẩn icon được tắt. Bật lại trong Cài đặt, mục Chung.")
    }

    /// While collapsed the windows are looked at again when either moves or the displays change; the hider waits for them to
    /// settle, since collapsing moves them too.
    private func observeLayout(of separatorItem: NSStatusItem, and toggleItem: NSStatusItem) {
        let center = NotificationCenter.default
        let changed: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.hider.layoutChanged() }
        }
        for window in [separatorItem.button?.window, toggleItem.button?.window].compactMap({ $0 }) {
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
                layoutObservers.append((center, center.addObserver(forName: name, object: window, queue: .main, using: changed)))
            }
        }
        layoutObservers.append((center, center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: changed
        )))
        let workspace = NSWorkspace.shared.notificationCenter
        layoutObservers.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: changed)))
    }

    private func stopObservingLayout() {
        layoutObservers.forEach { $0.center.removeObserver($0.token) }
        layoutObservers.removeAll()
    }

    @objc private func separatorClicked() { toggle() }
}

/// The real status item behind `MenuBarSeparator`.
private final class StatusItemSeparator: MenuBarSeparator {
    private let item: NSStatusItem
    private weak var toggle: NSStatusItem?

    init(item: NSStatusItem, toggle: NSStatusItem) {
        self.item = item
        self.toggle = toggle
    }

    var length: CGFloat {
        get { item.length }
        set { item.length = newValue }
    }

    var separatorFrame: CGRect? { Self.frame(of: item) }

    var toggleFrame: CGRect? { toggle.flatMap(Self.frame(of:)) }

    var screens: [MenuBarScreen] { MenuBarScreen.current() }

    /// The item's window frame, nil when it has none or is not shown. Whether the frame is on a menu bar is `MenuBarOrder`'s call.
    private static func frame(of item: NSStatusItem) -> CGRect? {
        guard let window = item.button?.window, window.isVisible else { return nil }
        return window.frame
    }
}

extension MenuBarScreen {
    /// The displays' menu bars as they are now. A display with a notch has a taller bar than the standard one.
    static func current() -> [MenuBarScreen] {
        NSScreen.screens.map {
            MenuBarScreen(frame: $0.frame, barHeight: max($0.safeAreaInsets.top, NSStatusBar.system.thickness))
        }
    }
}

/// Tells when the pointer gets on or off a menu bar, from mouse-moved events. Mouse monitors need no Accessibility
/// permission, and it runs only while "reveal on hover" is on.
private final class MenuBarHoverMonitor {
    var onChange: (Bool) -> Void = { _ in }
    private var monitors: [Any] = []
    private var screens: [MenuBarScreen] = []
    private var screenObserver: NSObjectProtocol?
    private var wasInside = false

    func setRunning(_ running: Bool) {
        running ? start() : stop()
    }

    private func start() {
        guard monitors.isEmpty else { return }
        refreshScreens()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshScreens() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.moved() }
        }) {
            monitors.append(global)
        }
        // The pointer over MyNotch's own icons is not reported to a global monitor.
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.moved() }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func stop() {
        guard !monitors.isEmpty else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        if wasInside {
            wasInside = false
            onChange(false)
        }
    }

    private func refreshScreens() {
        screens = MenuBarScreen.current()
    }

    private func moved() {
        let inside = MenuBarZone.contains(NSEvent.mouseLocation, in: screens)
        guard inside != wasInside else { return }
        wasInside = inside
        onChange(inside)
    }
}
