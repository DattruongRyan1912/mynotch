import AppKit
import MyNotchCore

/// What hides the icons left of the MyNotch icon, and what drives it: the settings, a click and the pointer on the menu bar.
/// There is no separator to drag: whatever is left of the MyNotch icon is hidden and listed in the bar under the menu bar
/// (`MenuBarItemsBarController`), and an icon dragged right of it stays shown. From macOS 27 the system takes those apps off
/// the menu bar itself (`MenuBarNativeHiding`); before it, an invisible status item kept just left of the MyNotch icon grows
/// long and pushes them off the screen. The rules (levels, timers, what is refused) are `MenuBarHider`'s.
final class MenuBarHiderController {
    /// Nothing collapses by itself for this long after the user turns the hider on: they are placing icons.
    private static let arrangingGrace: Duration = .seconds(60)
    /// The invisible separator's name, which is also where macOS keeps its place.
    private static let separatorName = "MyNotchSeparator"

    private let settings: SettingsStore
    private let scheduler: any Scheduler
    private let hider: MenuBarHider
    private let notice: MenuBarNotice
    /// The MyNotch icon, which toggles and marks where the hidden icons end.
    private var toggleItem: NSStatusItem?
    /// The invisible status item that pushes the icons away; nil where the system hides them (macOS 27).
    private var separatorItem: NSStatusItem?
    private var separator: StatusItemSeparator?
    private let hover = MenuBarHoverMonitor()
    /// The bar under the menu bar for the hidden icons; made once the rest of the controller exists.
    private(set) var itemsBar: MenuBarItemsBarController!
    /// Whether the setting was on at the last look, so only a switch-on gets the arranging grace, not a launch.
    private var wasEnabled: Bool
    /// ⌘-dragging the invisible separator off the menu bar clears its `isVisible`, which is mirrored into the setting.
    private var visibilityObservation: NSKeyValueObservation?
    /// The first separator after launch gets the "hide at start" state; one made later (the icon switched off and on) does not.
    private var isLaunching = true
    private var layoutObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init(settings: SettingsStore, scheduler: any Scheduler, notice: MenuBarNotice) {
        self.settings = settings
        self.scheduler = scheduler
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
        itemsBar = MenuBarItemsBarController(
            settings: settings, scheduler: scheduler, hider: hider, notice: notice,
            anchor: { [weak self] in self?.toggleItem?.button?.window?.frame },
            ownFrames: { [weak self] in
                // The separator's window counts only while it has its normal length; a long one's is not on the bar.
                guard let self else { return [] }
                return [toggleItem?.button?.window?.frame, hider.layout?.hiddenSeparator].compactMap { $0 }
            }
        )
        hider.onLevelChanged = { [weak self] in self?.itemsBar.sectionsChanged() }
        observeSettings()
        observeQuitting()
    }

    /// Whether the user switched the hider on. It works only while the MyNotch icon exists too, since that icon is how the
    /// hidden ones come back.
    var isEnabled: Bool { settings.value(MenuBarHiderSettings.enabled) }

    /// The MyNotch icon appeared or went away.
    func setToggleItem(_ item: NSStatusItem?) {
        toggleItem = item
        sync()
    }

    /// Whether a click on the MyNotch icon opens the bar under the menu bar instead of showing the hidden icons in place.
    var opensBar: Bool { itemsBar.isAvailable }

    /// The shortcut: opens or closes the bar, or, where the bar is off, hides or shows the hidden icons.
    func toggle() {
        if opensBar { toggleBar() } else { toggleInPlace() }
    }

    /// A plain click: opens or closes the bar. The bar sits on the menu bar, so opening it puts away the icons shown in place
    /// (just after the hider was switched on, at launch, after an ⌥-click), which would be drawn under the bar's. After the
    /// opening, so the move reaches the open bar and it reads the items again once they have gone.
    func toggleBar() {
        itemsBar.toggle()
        if itemsBar.bar.isOpen, !hider.isCollapsed { run(hider.collapse) }
    }

    /// Hides, or shows the hidden icons in the menu bar itself: an ⌥-click, the menu entry, and the click where there is no bar.
    func toggleInPlace() { run(hider.toggle) }

    /// A refused collapse says why, on the notch and to VoiceOver, instead of leaving a dead icon. Where the separator had moved
    /// away from the MyNotch icon, it is put back there for the next click.
    private func run(_ action: () -> Bool) {
        guard let separator, !action() else { return }
        NSSound.beep()
        if !separator.canHide {
            Log.logger(category: "app").notice("Menu-bar hider: not hiding, Accessibility is not granted")
            notice.show("Cần quyền Trợ năng để ẩn icon menu bar.")
            return
        }
        guard separatorItem != nil else {
            Log.logger(category: "app").notice("Menu-bar hider: not hiding, the MyNotch icon is not on a menu bar")
            notice.show("Không ẩn được icon: biểu tượng MyNotch không nằm trên menu bar.")
            return
        }
        Log.logger(category: "app").notice("Menu-bar hider: not hiding, the separator is not left of the MyNotch icon; putting it back")
        removeSeparator()
        addSeparator(quietFor: .zero)
        notice.show("Đã đặt lại chỗ ẩn icon bên trái biểu tượng MyNotch. Bấm lại để ẩn.")
    }

    var isCollapsed: Bool { hider.isCollapsed }

    /// Shows everything again, for the moments the app is going away and the icons must not stay hidden.
    func expandNow() { hider.revealAll() }

    private func observeSettings() {
        Task { [weak self, settings] in
            for await _ in Observations({
                (settings.value(MenuBarHiderSettings.enabled), settings.value(MenuBarHiderSettings.autoCollapseSeconds),
                 settings.value(MenuBarHiderSettings.revealOnHover), settings.value(MenuBarHiderSettings.itemsBar))
            }) {
                self?.sync()
                self?.hider.settingsChanged()
                self?.itemsBar.settingsChanged()
            }
        }
    }

    /// Whatever the way out is (quitting, shutting down), the icons come back first: the status item's length is never
    /// saved, but the wait for the modules to stop can last seconds. The system's restriction ends with the process anyway.
    private func observeQuitting() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.itemsBar.close()
                self?.hider.revealAll()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.itemsBar.close()
                self?.hider.revealAll()
            }
        }
    }

    private func sync() {
        let enabled = isEnabled
        let justEnabled = enabled && !wasEnabled
        wasEnabled = enabled
        let wanted = enabled && toggleItem != nil
        if wanted, separator == nil {
            addSeparator(quietFor: justEnabled ? Self.arrangingGrace : .zero)
        } else if !wanted, separator != nil {
            removeSeparator()
        }
        hover.setRunning(wanted && settings.value(MenuBarHiderSettings.revealOnHover))
    }

    private func addSeparator(quietFor grace: Duration) {
        guard let toggleItem else { return }
        let hidesNatively = StatusItemSeparator.fitsLength && MenuBarRestriction.isAvailable
        if !hidesNatively {
            separatorItem = makeSeparatorItem()
        }
        let separator = StatusItemSeparator(item: separatorItem, toggle: toggleItem, scheduler: scheduler, native: hidesNatively)
        separator.onSectionsChanged = { [weak self] in self?.itemsBar.sectionsChanged() }
        self.separator = separator
        observeLayout()
        let startingUp = isLaunching
        isLaunching = false
        hider.attach(separator, quietFor: grace, startingUp: startingUp)
    }

    /// The invisible status item, placed just left of the MyNotch icon: macOS keeps an item's place as its distance from the
    /// right end of the bar, so one point more than the icon's is the next place on its left.
    private func makeSeparatorItem() -> NSStatusItem {
        let defaults = UserDefaults.standard
        let iconPlace = defaults.object(forKey: "NSStatusItem Preferred Position MyNotchIcon") as? Double
        if let iconPlace { defaults.set(iconPlace + 1, forKey: "NSStatusItem Preferred Position \(Self.separatorName)") }
        let item = NSStatusBar.system.statusItem(withLength: StatusItemSeparator.restingLength)
        item.autosaveName = Self.separatorName
        // The name also keeps whether the item is shown, and a ⌘-drag off the bar stored "hidden" under it. The user's settings
        // say it should exist now, so it does.
        item.isVisible = true
        item.button?.setAccessibilityLabel("Dấu ngăn icon menu bar")
        // After the name and visibility are settled, so only the user's own removal is heard.
        visibilityObservation = item.observe(\.isVisible, options: [.new]) { [weak self] _, change in
            guard change.newValue == false else { return }
            Task { @MainActor in self?.separatorWasRemoved() }
        }
        return item
    }

    private func removeSeparator() {
        // The bar is for the icons the hider hides: with no hider there is nothing to open it from.
        itemsBar.close()
        visibilityObservation = nil
        stopObservingLayout()
        hider.detach()
        if let separatorItem { NSStatusBar.system.removeStatusItem(separatorItem) }
        separatorItem = nil
        separator = nil
    }

    /// The user dragged the invisible separator off the menu bar: with nothing to hide behind, the hider is off, and the user is told.
    private func separatorWasRemoved() {
        guard separatorItem != nil else { return }
        Log.logger(category: "app").notice("Menu-bar hider: the separator was removed from the menu bar, switching the hider off")
        settings.set(false, for: MenuBarHiderSettings.enabled)
        notice.show("Chỗ ẩn icon đã bị gỡ khỏi menu bar nên tính năng ẩn icon được tắt. Bật lại trong Cài đặt, mục Chung.")
    }

    /// While the separator is long the windows are looked at again when one moves or the displays change; the hider waits for
    /// them to settle, since collapsing moves them too.
    private func observeLayout() {
        stopObservingLayout()
        let center = NotificationCenter.default
        // A separator being measured moves its window with each probe; the layout is judged once the measurement is over.
        let changed: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.separator?.isMeasuring != true else { return }
                self.separator?.layoutChanged()
                self.hider.layoutChanged()
            }
        }
        let displaysChanged: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.separator?.displaysChanged()
                self?.hider.layoutChanged()
            }
        }
        for window in [separatorItem, toggleItem].compactMap({ $0?.button?.window }) {
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
                layoutObservers.append((center, center.addObserver(forName: name, object: window, queue: .main, using: changed)))
            }
        }
        layoutObservers.append((center, center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: displaysChanged
        )))
        let workspace = NSWorkspace.shared.notificationCenter
        layoutObservers.append((workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: changed)))
    }

    private func stopObservingLayout() {
        layoutObservers.forEach { $0.center.removeObserver($0.token) }
        layoutObservers.removeAll()
    }
}

/// What hides behind `MenuBarSeparator`: from macOS 27 the system, which takes the apps left of the MyNotch icon off the menu
/// bar (`MenuBarNativeHiding` through `MenuBarRestriction`), with no status item of its own; before it, the invisible item
/// growing long. On a macOS 27 without the restriction, that item gets the length that still fits on the bar
/// (`MenuBarFittedLength`), since the system drops a longer one instead of letting it push.
private final class StatusItemSeparator: MenuBarSeparator {
    /// Whether the system drops an over-long status item instead of pushing the items on its left away.
    static let fitsLength = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    /// The invisible item's length while it hides nothing: macOS still keeps its margins around it.
    static let restingLength: CGFloat = 0

    private let item: NSStatusItem?
    private weak var toggle: NSStatusItem?
    private let native: MenuBarNativeHiding?
    /// The system refused the restriction once: nothing is hidden from then on, until MyNotch starts again.
    private var nativeFailed = false
    private let fitted: MenuBarFittedLength?
    /// Lets the clock open Notification Center while the system hides apps.
    private let clockTap: MenuBarClockTap?
    private var wantsLong = false
    /// A measurement ended or the system hid other apps: what is hidden changed.
    var onSectionsChanged: (() -> Void)?

    init(item: NSStatusItem?, toggle: NSStatusItem, scheduler: any Scheduler, native hidesNatively: Bool) {
        self.item = item
        self.toggle = toggle
        native = hidesNatively
            ? MenuBarNativeHiding(
                provider: MenuBarRestriction(), source: AccessibilityMenuBarItemSource(),
                runningApps: { NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier) },
                ownBundleID: Bundle.main.bundleIdentifier ?? ""
            )
            : nil
        clockTap = native.map { native in
            MenuBarClockTap(scheduler: scheduler, suspend: { native.suspend() }, resume: { native.resume() })
        }
        fitted = item.flatMap { item in
            guard Self.fitsLength else { return nil }
            return MenuBarFittedLength(probe: StatusItemProbe(item: item), scheduler: scheduler, normalLength: Self.restingLength)
        }
        fitted?.onMeasured = { [weak self] in
            let length = self?.fitted?.fitted.map { "\(Int($0))" } ?? "none"
            Log.logger(category: "app").notice("Menu-bar hider: measured the separator length that fits: \(length, privacy: .public)")
            self?.onSectionsChanged?()
        }
        native?.onChanged = { [weak self] in
            // Counts only: which apps the user hides is nobody's business but theirs.
            Log.logger(category: "app").notice("Menu-bar hider: the system hides \(self?.native?.hiddenApps.count ?? 0) apps")
            self?.clockTap?.setRunning(self?.native?.isRestricted == true)
            self?.onSectionsChanged?()
        }
        native?.onFailed = { [weak self] in
            Log.logger(category: "app").error("Menu-bar hider: the system's restriction failed, nothing is hidden")
            self?.nativeFailed = true
        }
    }

    var length: CGFloat {
        get { item?.length ?? Self.restingLength }
        set {
            let long = newValue == MenuBarHider.collapsedLength
            wantsLong = long
            if let native {
                native.apply(long && canHide ? .collapsed : .all) { [weak self] in
                    MenuBarLayout(screens: MenuBarScreen.current(), hiddenSeparator: self?.separatorFrame)
                }
            } else if let fitted {
                fitted.apply(long: long)
            } else {
                item?.length = long ? newValue : Self.restingLength
            }
        }
    }

    /// The invisible item's window; where the system hides, a sliver just left of the MyNotch icon, which is where what is
    /// hidden ends.
    var separatorFrame: CGRect? {
        if let item { return Self.frame(of: item) }
        guard let icon = toggleFrame else { return nil }
        return CGRect(x: icon.minX - 1, y: icon.minY, width: 1, height: icon.height)
    }

    var toggleFrame: CGRect? { toggle.flatMap(Self.frame(of:)) }

    var screens: [MenuBarScreen] { MenuBarScreen.current() }

    var hasAlwaysHiddenSection: Bool { false }

    var alwaysHiddenLength: CGFloat {
        get { Self.restingLength }
        set {}
    }

    var alwaysHiddenFrame: CGRect? { nil }

    /// Where the system hides, it reads which apps are left of the MyNotch icon through Accessibility, and needs it.
    var canHide: Bool {
        guard native != nil else { return true }
        return !nativeFailed && AXIsProcessTrusted()
    }

    var hiddenApps: [String: MenuBarSection]? {
        guard let native, native.isRestricted else { return nil }
        return native.hiddenApps
    }

    /// Whether the separator is being measured: its window moves with each probe, which says nothing about the layout.
    var isMeasuring: Bool { fitted?.isMeasuring == true }

    /// A window moved: a long separator looks whether the system has dropped it since.
    func layoutChanged() { fitted?.layoutChanged() }

    /// The displays changed: the length that fits is measured again.
    func displaysChanged() {
        fitted?.forget()
        clockTap?.displaysChanged()
    }

    /// The item's window frame, nil when it has none or is not shown. Whether the frame is on a menu bar is `MenuBarOrder`'s call.
    private static func frame(of item: NSStatusItem) -> CGRect? {
        guard let window = item.button?.window, window.isVisible else { return nil }
        return window.frame
    }
}

/// A status item's length and where its button is, for `MenuBarFittedLength`.
private final class StatusItemProbe: MenuBarLengthProbe {
    private let item: NSStatusItem

    init(item: NSStatusItem) { self.item = item }

    var length: CGFloat {
        get { item.length }
        set { item.length = newValue }
    }

    var trailingEdge: CGFloat? { buttonFrame?.maxX }

    var room: CGFloat? {
        guard let frame = buttonFrame,
              let screen = NSScreen.screens.first(where: { $0.frame.minX <= frame.maxX && frame.maxX <= $0.frame.maxX }) else { return nil }
        return frame.maxX - screen.frame.minX
    }

    /// The button in screen points: the window around it has a margin on each side.
    private var buttonFrame: CGRect? {
        guard let button = item.button, let window = button.window, window.isVisible else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
}

extension MenuBarScreen {
    /// The displays' menu bars as they are now. A display with a notch has a taller bar than the standard one, and a gap the notch covers.
    static func current() -> [MenuBarScreen] {
        NSScreen.screens.map {
            MenuBarScreen(
                frame: $0.frame, barHeight: max($0.safeAreaInsets.top, NSStatusBar.system.thickness),
                notchGap: $0.safeAreaInsets.top > 0
                    ? MenuBarScreen.notchGap(frame: $0.frame, leftWidth: $0.auxiliaryTopLeftArea?.width, rightWidth: $0.auxiliaryTopRightArea?.width)
                    : nil
            )
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
