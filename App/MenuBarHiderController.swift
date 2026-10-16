import AppKit
import MyNotchCore

/// The separator status items ‹ (and, when switched on, ‹‹ for the always-hidden zone) and what drives them: the settings, a
/// click on them and the pointer on the menu bar. The rules (lengths, timers, what is refused) are `MenuBarHider`'s; this
/// only owns the real items and the event monitors.
final class MenuBarHiderController {
    /// Nothing collapses by itself for this long after the user turns the hider on: they are placing icons.
    private static let arrangingGrace: Duration = .seconds(60)

    private let settings: SettingsStore
    private let hider: MenuBarHider
    private let notice: MenuBarNotice
    /// The MyNotch icon, which toggles; the separator is created after it, so the system lays it out on its left.
    private var toggleItem: NSStatusItem?
    private var separatorItem: NSStatusItem?
    /// ‹‹, further left than ‹ (it is made after it), while the always-hidden zone is switched on.
    private var alwaysItem: NSStatusItem?
    private var separator: StatusItemSeparator?
    private let hover = MenuBarHoverMonitor()
    /// Whether the setting was on at the last look, so only a switch-on gets the arranging grace, not a launch.
    private var wasEnabled: Bool
    /// ⌘-dragging "‹" off the menu bar clears its `isVisible`, which is mirrored into the setting.
    private var visibilityObservation: NSKeyValueObservation?
    private var alwaysVisibilityObservation: NSKeyValueObservation?
    /// The first separator after launch gets the "hide at start" state; one made later (the icon switched off and on) does not.
    private var isLaunching = true
    private var layoutObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init(settings: SettingsStore, scheduler: any Scheduler, notice: MenuBarNotice) {
        self.settings = settings
        self.notice = notice
        wasEnabled = settings.value(MenuBarHiderSettings.enabled)
        // Asked only when an auto-collapse comes due, so the pointer is not watched for it.
        hider = MenuBarHider(settings: settings, scheduler: scheduler, isPointerOnMenuBar: {
            MenuBarZone.contains(NSEvent.mouseLocation, in: MenuBarScreen.current())
        })
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

    /// A click on the MyNotch icon or the shortcut: hides, or shows the hidden zone.
    func toggle() { run(hider.toggle) }

    /// An ⌥-click or the menu entry: shows the always-hidden zone too, or puts it away again.
    func toggleAll() { run(hider.toggleAll) }

    /// A refused collapse (the separators are not in order) says what to do, on the notch and to VoiceOver, instead of leaving
    /// a dead icon.
    private func run(_ action: () -> Bool) {
        guard separatorItem != nil else { return }
        if !action() {
            Log.logger(category: "app").notice("Menu-bar hider: not hiding, the separators are not in order left of the MyNotch icon")
            NSSound.beep()
            notice.show(alwaysItem == nil
                ? "Kéo dấu ‹ sang trái biểu tượng MyNotch (giữ ⌘)"
                : "Kéo dấu ‹‹ sang trái dấu ‹, và dấu ‹ sang trái biểu tượng MyNotch (giữ ⌘)")
        }
    }

    var isCollapsed: Bool { hider.isCollapsed }

    /// Whether the always-hidden zone is shown now, which the menu entry's title follows.
    var isShowingAlwaysHidden: Bool { hider.level == .all }

    /// Shows everything again, both zones, for the moments the app is going away and the icons must not stay hidden.
    func expandNow() { hider.revealAll() }

    private func observeSettings() {
        Task { [weak self, settings] in
            for await _ in Observations({
                (settings.value(MenuBarHiderSettings.enabled), settings.value(MenuBarHiderSettings.autoCollapseSeconds),
                 settings.value(MenuBarHiderSettings.revealOnHover), settings.value(MenuBarHiderSettings.alwaysHiddenSection))
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
            MainActor.assumeIsolated { self?.hider.revealAll() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hider.revealAll() }
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
        } else if wanted {
            syncAlwaysHidden()
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
        // ‹‹ after ‹, so the system lays it out further left.
        if settings.value(MenuBarHiderSettings.alwaysHiddenSection) { addAlwaysItem() }
        observeLayout()
        let startingUp = isLaunching
        isLaunching = false
        hider.attach(separator, quietFor: grace, startingUp: startingUp)
    }

    private func removeSeparator() {
        visibilityObservation = nil
        alwaysVisibilityObservation = nil
        stopObservingLayout()
        hider.detach()
        if let alwaysItem { NSStatusBar.system.removeStatusItem(alwaysItem) }
        if let separatorItem { NSStatusBar.system.removeStatusItem(separatorItem) }
        alwaysItem = nil
        separatorItem = nil
        separator = nil
    }

    /// The always-hidden zone was switched on or off while the separator exists.
    private func syncAlwaysHidden() {
        let wanted = settings.value(MenuBarHiderSettings.alwaysHiddenSection)
        if wanted, alwaysItem == nil {
            addAlwaysItem()
            observeLayout()
            // Empty and at the far left: everything is shown for a while, so icons can be dragged to its left.
            hider.alwaysHiddenSectionChanged(quietFor: Self.arrangingGrace)
        } else if !wanted, let alwaysItem {
            alwaysVisibilityObservation = nil
            NSStatusBar.system.removeStatusItem(alwaysItem)
            self.alwaysItem = nil
            separator?.alwaysItem = nil
            observeLayout()
            hider.alwaysHiddenSectionChanged()
        }
    }

    private func addAlwaysItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Its own fixed name and visibility, for the same reasons as ‹.
        item.autosaveName = "MyNotchAlwaysHiddenSeparator"
        item.isVisible = true
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "chevron.left.2", accessibilityDescription: "Dấu ngăn vùng luôn ẩn")
            if button.image == nil { button.title = "‹‹" }
            button.toolTip = "Vùng luôn ẩn: giữ ⌥ và bấm icon MyNotch để hiện nó, rồi giữ ⌘ và kéo icon của app khác sang bên trái dấu này."
            button.target = self
            button.action = #selector(alwaysSeparatorClicked)
        }
        alwaysItem = item
        separator?.alwaysItem = item
        alwaysVisibilityObservation = item.observe(\.isVisible, options: [.new]) { [weak self] _, change in
            guard change.newValue == false else { return }
            Task { @MainActor in self?.alwaysSeparatorWasRemoved() }
        }
    }

    /// The user dragged ‹‹ off the menu bar: the always-hidden zone is off, and the user is told.
    private func alwaysSeparatorWasRemoved() {
        guard alwaysItem != nil else { return }
        Log.logger(category: "app").notice("Menu-bar hider: the always-hidden separator was removed from the menu bar, switching that zone off")
        settings.set(false, for: MenuBarHiderSettings.alwaysHiddenSection)
        notice.show("Dấu ‹‹ đã bị gỡ khỏi menu bar nên vùng luôn ẩn được tắt. Bật lại trong Cài đặt, mục Chung.")
    }

    /// The user dragged "‹" off the menu bar: with nothing to hide behind, the hider is off, and the user is told.
    private func separatorWasRemoved() {
        guard separatorItem != nil else { return }
        Log.logger(category: "app").notice("Menu-bar hider: the separator was removed from the menu bar, switching the hider off")
        settings.set(false, for: MenuBarHiderSettings.enabled)
        notice.show("Dấu ‹ đã bị gỡ khỏi menu bar nên tính năng ẩn icon được tắt. Bật lại trong Cài đặt, mục Chung.")
    }

    /// While a separator is long the windows are looked at again when one moves or the displays change; the hider waits for
    /// them to settle, since collapsing moves them too. Registered again whenever ‹‹ comes or goes.
    private func observeLayout() {
        stopObservingLayout()
        let center = NotificationCenter.default
        let changed: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.hider.layoutChanged() }
        }
        for window in [separatorItem, alwaysItem, toggleItem].compactMap({ $0?.button?.window }) {
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

    /// A click on ‹ toggles like the MyNotch icon; with ⌥ the always-hidden zone too.
    @objc private func separatorClicked() {
        NSApp.currentEvent?.modifierFlags.contains(.option) == true ? toggleAll() : toggle()
    }

    @objc private func alwaysSeparatorClicked() { toggleAll() }
}

/// The real status item behind `MenuBarSeparator`.
private final class StatusItemSeparator: MenuBarSeparator {
    private let item: NSStatusItem
    private weak var toggle: NSStatusItem?

    /// ‹‹, set while the always-hidden zone is on.
    var alwaysItem: NSStatusItem?

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

    var hasAlwaysHiddenSection: Bool { alwaysItem != nil }

    var alwaysHiddenLength: CGFloat {
        get { alwaysItem?.length ?? NSStatusItem.variableLength }
        set { alwaysItem?.length = newValue }
    }

    var alwaysHiddenFrame: CGRect? { alwaysItem.flatMap(Self.frame(of:)) }

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
