import AppKit
import MyNotchCore

/// The separator status item ‹ and what drives it: the settings, a click on it and the pointer on the menu bar. The rules
/// (lengths, timers, what is refused) are `MenuBarHider`'s; this only owns the real item and the event monitors.
final class MenuBarHiderController {
    private let settings: SettingsStore
    private let hider: MenuBarHider
    /// The MyNotch icon, which toggles; the separator is created after it, so the system lays it out on its left.
    private var toggleItem: NSStatusItem?
    private var separatorItem: NSStatusItem?
    private var separator: StatusItemSeparator?
    private let hover = MenuBarHoverMonitor()

    init(settings: SettingsStore, scheduler: any Scheduler) {
        self.settings = settings
        hider = MenuBarHider(settings: settings, scheduler: scheduler)
        hover.onChange = { [weak self] inside in self?.hider.pointerMoved(inMenuBar: inside) }
        observeSettings()
    }

    /// Whether the user switched the hider on. The separator exists only while the MyNotch icon does too, since that icon is
    /// how the hidden ones come back.
    var isEnabled: Bool { settings.value(MenuBarHiderSettings.enabled) }

    /// The MyNotch icon appeared or went away.
    func setToggleItem(_ item: NSStatusItem?) {
        toggleItem = item
        sync()
    }

    /// A click on the MyNotch icon or the shortcut. A refused collapse (the separator was dragged to the right of the icon)
    /// beeps instead of hiding the way back.
    func toggle() {
        guard separatorItem != nil else { return }
        if !hider.toggle() {
            Log.logger(category: "app").notice("Menu-bar hider: not collapsing, the separator is not left of the MyNotch icon")
            NSSound.beep()
        }
    }

    var isCollapsed: Bool { hider.isCollapsed }

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

    private func sync() {
        let wanted = isEnabled && toggleItem != nil
        if wanted, separatorItem == nil {
            addSeparator()
        } else if !wanted, separatorItem != nil {
            removeSeparator()
        }
        hover.setRunning(wanted && settings.value(MenuBarHiderSettings.revealOnHover))
    }

    private func addSeparator() {
        guard let toggleItem else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // A fixed name, so macOS keeps where the user dragged it across launches whatever order the items are made in.
        item.autosaveName = "MyNotchSeparator"
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
        hider.attach(separator)
    }

    private func removeSeparator() {
        hider.detach()
        if let separatorItem { NSStatusBar.system.removeStatusItem(separatorItem) }
        separatorItem = nil
        separator = nil
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

    /// Compared by the two items' windows, which the system places once the items have been laid out; without both, it
    /// cannot be told, and hiding then could hide the way back, so the answer is no.
    var isLeftOfToggle: Bool {
        guard let own = item.button?.window, let other = toggle?.button?.window, own.isVisible, other.isVisible else { return false }
        return own.frame.midX < other.frame.midX
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
        // A display with a notch has a taller menu bar than the standard one.
        screens = NSScreen.screens.map {
            MenuBarScreen(frame: $0.frame, barHeight: max($0.safeAreaInsets.top, NSStatusBar.system.thickness))
        }
    }

    private func moved() {
        let inside = MenuBarZone.contains(NSEvent.mouseLocation, in: screens)
        guard inside != wasInside else { return }
        wasInside = inside
        onChange(inside)
    }
}
