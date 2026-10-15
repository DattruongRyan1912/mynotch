import AppKit
import NotchUI
import SwiftUI

/// Where the chip appears; a protocol so tests never put a window on a screen.
protocol SelectionChipWindowing: AnyObject {
    /// Puts the chip beside `anchor` (AppKit coordinates), or moves and updates it when it is already up.
    func show(_ content: SelectionChipContent, near anchor: CGRect)
    func hide()
}

/// Borderless, floating over every Space, and never key: clicking it must not take the keyboard from the app the text is
/// selected in, or that app would grey the selection out and swallow nothing the user types.
final class SelectionChipPanel: NSPanel {
    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 200, height: 32), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        // On every Space and next to full-screen apps, and left out of Mission Control's list.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        isReleasedWhenClosed = false
        // MyNotch is not the active app while the chip is up, and a panel that hid then would never show.
        hidesOnDeactivate = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        title = "Gợi ý khi bôi đen"
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosts the chip's view: accepts the first click although MyNotch is not active, and reports the pointer coming and going
/// even then (a tracking area that is `activeAlways`, which SwiftUI's own hover is not guaranteed to be). A menu of the chip
/// ("⋯") moves the pointer off the panel, so while any menu is open the chip counts as hovered, and it is let go the way the
/// pointer's leaving is when the menu ends with the pointer elsewhere.
final class SelectionChipHostingView: NSHostingView<AnyView> {
    var hover: @MainActor (Bool) -> Void = { _ in }
    private var pointerArea: NSTrackingArea?
    private var notifications = NotificationCenter.default
    private var pointerIsOverChip: () -> Bool = { false }
    private var menuObservers: [any NSObjectProtocol] = []

    convenience init(
        rootView: AnyView, notifications: NotificationCenter = .default, pointerIsOverChip: (() -> Bool)? = nil,
        hover: @escaping @MainActor (Bool) -> Void
    ) {
        self.init(rootView: rootView)
        self.hover = hover
        self.notifications = notifications
        self.pointerIsOverChip = pointerIsOverChip ?? { [weak self] in
            self.map { $0.window?.frame.contains(NSEvent.mouseLocation) ?? false } ?? false
        }
    }

    isolated deinit {
        stopObservingMenus()
    }

    /// Menus are only listened for while the chip is in a window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObservingMenus()
        if window != nil { observeMenus() }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea { removeTrackingArea(pointerArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        pointerArea = area
    }

    override func mouseEntered(with event: NSEvent) { pointerEntered() }
    override func mouseExited(with event: NSEvent) { pointerExited() }

    func pointerEntered() { hover(true) }
    func pointerExited() { hover(false) }

    private func stopObservingMenus() {
        menuObservers.forEach(notifications.removeObserver)
        menuObservers = []
    }

    private func observeMenus() {
        menuObservers = [
            notifications.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.hover(true) }
            },
            notifications.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.pointerIsOverChip() else { return }
                    self.hover(false)
                }
            },
        ]
    }
}

/// The real chip window: one panel while a chip is up, made when it first shows and dropped when it goes, so a hidden
/// chip holds no views.
final class SystemSelectionChipWindow: SelectionChipWindowing {
    private let interface: NotchInterface
    private let screens: () -> [ScreenArea]
    private(set) var panel: SelectionChipPanel?
    private var hosting: SelectionChipHostingView?
    private var follower: CaptureHidingFollower?

    /// `interface` is where the "hide from screen recording" setting and the accent come from: the app's shared one, or a
    /// test's own.
    init(interface: NotchInterface = .shared, screens: @escaping () -> [ScreenArea] = { SmartSelectionSetup.systemScreens() }) {
        self.interface = interface
        self.screens = screens
    }

    func show(_ content: SelectionChipContent, near anchor: CGRect) {
        place(content, near: anchor)
        panel?.orderFrontRegardless()
    }

    /// Everything `show` does except putting the panel on screen: its content, its size and its place. Returns the frame the
    /// panel has, which the system aligns to whole pixels.
    @discardableResult
    func place(_ content: SelectionChipContent, near anchor: CGRect) -> CGRect {
        let (panel, hosting) = panelAndHosting()
        hosting.hover = content.hover
        // A translation may be tall: it takes the room beside the selection, at most, and scrolls past that.
        let displays = screens()
        let room = min(SelectionChipLayout.maxHeight, SelectionGeometry.room(besides: anchor, screens: displays))
        hosting.rootView = AnyView(SelectionChipView(content: content, interface: interface, maxHeight: room))
        let frame = SelectionGeometry.chipFrame(size: hosting.fittingSize, anchor: anchor, screens: displays)
        panel.setFrame(frame, display: true)
        return panel.frame
    }

    func hide() {
        guard let panel else { return }
        self.panel = nil
        hosting = nil
        follower?.stop()
        follower = nil
        panel.orderOut(nil)
        // Usually hidden from inside one of its own buttons, so its views are let go on the next turn.
        Task { panel.contentView = nil }
    }

    private func panelAndHosting() -> (SelectionChipPanel, SelectionChipHostingView) {
        if let panel, let hosting { return (panel, hosting) }
        let panel = SelectionChipPanel()
        // Out of recordings the way the user asked before it can be shown. It belongs to the collapsed notch's world, a
        // widget beside the text the user is reading, so "when collapsed" hides it.
        follower = CaptureHidingFollower(panel, as: .compact, interface: interface)
        let hosting = SelectionChipHostingView(rootView: AnyView(EmptyView()))
        panel.contentView = hosting
        self.panel = panel
        self.hosting = hosting
        return (panel, hosting)
    }
}
