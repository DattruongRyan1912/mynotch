import AppKit
import MyNotchCore
import NotchUI
import SwiftUI

/// The bar under the menu bar that holds the icons the notch hides: its window, and the things that live only while it is open (the
/// monitors that hear Esc and a click elsewhere, the notifications that say the list may have changed). What it lists, when it
/// closes and what a click does are `MenuBarItemsBar`'s; this owns the window and the real Accessibility and capture adapters.
final class MenuBarItemsBarController {
    let bar: MenuBarItemsBar
    private let settings: SettingsStore
    private let notice: MenuBarNotice
    private let interface: NotchInterface
    private let permissions = SystemPermissionCenter()
    /// The MyNotch icon's window, which the bar hangs under.
    private let anchor: () -> CGRect?
    /// The windows of MyNotch's own status items that are on a bar now: a click on one of them toggles the bar, it is not a click
    /// elsewhere that closes it.
    private let ownFrames: () -> [CGRect]

    private var panel: MenuBarItemsBarPanel?
    private let icons = MenuBarAppIcons()
    private var monitors: [Any] = []
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var layoutTask: Task<Void, Never>?

    init(
        settings: SettingsStore, scheduler: any Scheduler, hider: MenuBarHider, notice: MenuBarNotice,
        interface: NotchInterface = .shared, anchor: @escaping () -> CGRect?, ownFrames: @escaping () -> [CGRect]
    ) {
        self.settings = settings
        self.notice = notice
        self.interface = interface
        self.anchor = anchor
        self.ownFrames = ownFrames
        var barPanelFrame: () -> CGRect? = { nil }
        bar = MenuBarItemsBar(
            source: AccessibilityMenuBarItemSource(), images: ScreenCaptureMenuBarItemImages(), sections: hider,
            settings: settings, scheduler: scheduler,
            layout: { hider.layout ?? MenuBarLayout(screens: MenuBarScreen.current()) },
            isPointerOnBar: { barPanelFrame().map { $0.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) } ?? false }
        )
        barPanelFrame = { [weak self] in self?.panel?.frame }
        bar.onOpenChanged = { [weak self] isOpen in isOpen ? self?.show() : self?.hide() }
        bar.onPressFailed = { [weak self] in self?.notice.show("Không mở được menu của icon này.") }
    }

    /// Whether a click on the MyNotch icon, ‹ or the shortcut opens the bar rather than showing the hidden icons in the menu bar:
    /// the hider and the setting are on, and Accessibility is granted, since the icons are listed through it.
    var isAvailable: Bool {
        MenuBarItemsBar.isAvailable(
            hiderOn: settings.value(MenuBarHiderSettings.enabled), settingOn: settings.value(MenuBarHiderSettings.itemsBar),
            accessibilityGranted: permissions.status(of: .accessibility) == .granted
        )
    }

    func toggle() { bar.toggle() }

    /// The hider moved a section, so which icons are on the bar changed.
    func sectionsChanged() { bar.itemsMayHaveChanged() }

    /// The delay or one of the settings changed: the bar follows the delay, and goes if it is not wanted any more.
    func settingsChanged() {
        if !isAvailable { bar.close(.unavailable) }
        bar.settingsChanged()
    }

    func close() { bar.close(.unavailable) }

    // MARK: the window

    private func show() {
        let panel = MenuBarItemsBarPanel(interface: interface)
        let content = MenuBarItemsBarView(bar: bar, interface: interface, icons: icons) { [weak self] in
            self?.bar.close(.itemChosen)
            Task { _ = await SystemPermissionCenter().request(.accessibility) }
        }
        let hosting = MenuBarItemsBarHostingView(rootView: content)
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: MenuBarItemsBarMetrics.messageSize)
        panel.contentView = hosting
        self.panel = panel
        layoutPanel()
        panel.orderFrontRegardless()
        installMonitors()
        observeBar()
    }

    private func hide() {
        removeMonitors()
        layoutTask?.cancel()
        layoutTask = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    /// The window is as big as what the bar holds, right-aligned under the MyNotch icon (`MenuBarItemsBarPlacement`).
    private func layoutPanel() {
        guard let panel else { return }
        let widths: [CGFloat] = bar.phase == .ready
            ? bar.entries.map { MenuBarItemsBarCell.width(of: $0, hasImage: bar.images[$0.id] != nil) }
            : []
        let size = MenuBarItemsBarMetrics.contentSize(cellWidths: widths)
        panel.setFrame(MenuBarItemsBarPlacement.frame(content: size, anchor: anchor(), screens: MenuBarScreen.current()), display: true)
    }

    // MARK: while open

    private func observeBar() {
        layoutTask = Task { [weak self, bar] in
            for await _ in Observations({ (bar.phase, bar.entries, bar.images.count) }) {
                self?.layoutPanel()
                // Counts only: what the items are called is nobody's business but the user's.
                if bar.phase == .ready {
                    Log.logger(category: "app").info("Menu-bar items bar: \(bar.entries.count) items listed, \(bar.images.count) captured")
                }
            }
        }
    }

    /// Esc and a click anywhere but on the bar close it. Both are heard by monitors that live only as long as the bar is open: the
    /// global ones see what happens in other apps (the key one needs the Accessibility permission the bar needs anyway), the local
    /// ones what happens in MyNotch's own windows. Nothing here is polled.
    private func installMonitors() {
        removeMonitors()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.clicked(at: NSEvent.mouseLocation) }
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.clicked(at: NSEvent.mouseLocation) }
            return event
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pressed(event.keyCode) }
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pressed(event.keyCode) }
            return event
        }) {
            monitors.append(monitor)
        }
        let changed: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.bar.itemsMayHaveChanged()
                self?.layoutPanel()
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main, using: changed)))
        }
        let center = NotificationCenter.default
        observers.append((center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: changed)))
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
    }

    private func clicked(at point: CGPoint) {
        guard let panel, !panel.frame.contains(point), !ownFrames().contains(where: { $0.contains(point) }) else { return }
        bar.close(.clickOutside)
    }

    /// 53 is Esc.
    private func pressed(_ keyCode: UInt16) {
        if keyCode == 53 { bar.close(.escape) }
    }
}
