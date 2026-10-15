import AppKit
import MyNotchCore
import NotchUI
import SwiftUI

/// The floating lyrics panel's window: borderless, above other windows on every space, and never the key window, so it does
/// not take the keyboard from the app in front or activate MyNotch.
final class LyricsFloatingPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        // The content draws its own rounded background; a window shadow would not follow its corners.
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        minSize = LyricsPanelPlacement.minimumSize
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets a drag that starts anywhere in the panel move it: the lyrics have no controls to click.
final class LyricsHostingView: NSHostingView<AnyView> {
    override var mouseDownCanMoveWindow: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The panel's content view: the lyrics, and over them a small close button that is there only while the pointer is over the
/// panel, with the same choice in a context menu. Both are AppKit's, since a drag that starts anywhere moves the window and
/// the button must still be a button.
final class LyricsPanelContainer: NSView {
    static let closeTitle = "Đóng bảng lời"
    private static let buttonSize: CGFloat = 20
    private static let buttonInset: CGFloat = 8

    let hosting: LyricsHostingView
    let closeButton: NSButton
    private let close: () -> Void

    init(hosting: LyricsHostingView, close: @escaping () -> Void) {
        self.hosting = hosting
        self.close = close
        closeButton = NSButton(frame: .zero)
        super.init(frame: .zero)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: Self.closeTitle)
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.contentTintColor = .white
        closeButton.toolTip = Self.closeTitle
        closeButton.setAccessibilityLabel(Self.closeTitle)
        closeButton.target = self
        closeButton.action = #selector(closePressed)
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = Self.buttonSize / 2
        closeButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        closeButton.isHidden = true
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        closeButton.frame = CGRect(
            x: bounds.maxX - Self.buttonInset - Self.buttonSize, y: bounds.maxY - Self.buttonInset - Self.buttonSize,
            width: Self.buttonSize, height: Self.buttonSize
        )
        addSubview(closeButton)

        let menu = NSMenu()
        let item = NSMenuItem(title: Self.closeTitle, action: #selector(closePressed), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        self.menu = menu
        hosting.menu = menu
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var mouseDownCanMoveWindow: Bool { true }

    /// The button is shown while the pointer is over the panel, even when another app is the active one.
    func setHovering(_ isHovering: Bool) {
        closeButton.isHidden = !isHovering
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { setHovering(true) }
    override func mouseExited(with event: NSEvent) { setHovering(false) }

    @objc private func closePressed() {
        close()
    }
}

/// Owns the lyrics panel while it is up: one panel, made when it is shown and let go when it is hidden, so a hidden panel holds
/// no views and costs nothing. It puts the panel where the user left it on each display and remembers where they leave it
/// next, keeps it out of recordings the way the user asked for the notch, and applies the opacity and the click-through setting.
/// It tells the panel's views whether it can be seen (`presence`), which the occlusion of its window, sleeping displays and a locked
/// screen decide, and it keeps the panel on a display that is there.
final class LyricsPanelController {
    /// A move or a resize is remembered this long after the last of its steps, so a drag is one write and not a hundred.
    static let saveDelay: Duration = .milliseconds(400)
    /// Dimmer than this the panel is hard to find again.
    static let opacityRange = 0.3...1.0

    private let interface: NotchInterface
    private let scheduler: any Scheduler
    private let displays: @MainActor () -> [PanelDisplay]
    private let present: (NSPanel) -> Void
    private let onPlacementChange: (LyricsPanelPlacement) -> Void
    /// The close button or the menu was used; the owner takes the panel down. Settable, since the owner may need itself to do it.
    var onCloseRequested: () -> Void
    private let systemEvents: SystemPresenceEvents
    private let windowIsVisible: (NSWindow) -> Bool
    private var stopSystemEvents: (() -> Void)?
    private var placement: LyricsPanelPlacement
    private var opacity = 1.0
    private var clickThrough = false
    private var follower: CaptureHidingFollower?
    private var observers: [NSObjectProtocol] = []
    private var pendingSave: ScheduledAction?
    /// The panel is being put in place, which is not the user moving it.
    private var isPlacing = false
    /// The displays changed a moment ago: the system moves the panel itself when its display goes, and that is not the user either.
    private var isRelocating = false
    private var relocationEnd: ScheduledAction?
    private(set) var panel: LyricsFloatingPanel?
    /// Whether the panel can be seen, for its views.
    let presence = LyricsPanelPresence()
    /// How long after the displays change the panel's own moves are taken to be the system's.
    static let relocationSettle: Duration = .seconds(1)

    var isShown: Bool { panel != nil }

    /// - Parameters:
    ///   - interface: where the "hide from screen recording" setting comes from: the app's shared one, or a test's own.
    ///   - displays: the displays now, the main one first.
    ///   - present: puts the panel on the screen; tests record it instead.
    ///   - onPlacementChange: hears the placement with the new frame in it, to store.
    ///   - onCloseRequested: the close button or the menu was used; the owner takes the panel down.
    ///   - systemEvents: where sleeping displays and the lock screen are heard.
    ///   - windowIsVisible: whether the window is shown and not covered.
    init(
        interface: NotchInterface = .shared,
        scheduler: any Scheduler,
        placement: LyricsPanelPlacement,
        displays: @escaping @MainActor () -> [PanelDisplay] = LyricsPanelController.screens,
        present: @escaping (NSPanel) -> Void = { $0.orderFrontRegardless() },
        onPlacementChange: @escaping (LyricsPanelPlacement) -> Void,
        onCloseRequested: @escaping () -> Void = {},
        systemEvents: SystemPresenceEvents = .system,
        windowIsVisible: @escaping (NSWindow) -> Bool = { $0.isVisible && $0.occlusionState.contains(.visible) }
    ) {
        self.interface = interface
        self.scheduler = scheduler
        self.placement = placement
        self.displays = displays
        self.present = present
        self.onPlacementChange = onPlacementChange
        self.onCloseRequested = onCloseRequested
        self.systemEvents = systemEvents
        self.windowIsVisible = windowIsVisible
    }

    /// The screens as the panel sees them, the main one first.
    static func screens() -> [PanelDisplay] {
        NSScreen.screens.map { screen in
            PanelDisplay(key: key(of: screen), frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
    }

    /// The display's UUID, which stays the same when it is unplugged and plugged in again; its number does not.
    private static func key(of screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return "unknown" }
        let id = number.uint32Value
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return String(id) }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// Shows the panel with `content`, where it was left. Showing what is up already only brings it forward.
    func show(content: AnyView) {
        if let panel {
            present(panel)
            return
        }
        let frame = placement.restoredFrame(among: displays())
        let panel = LyricsFloatingPanel(frame: frame)
        let hosting = LyricsHostingView(rootView: content)
        // The window's size is the user's, not what the lyrics ask for.
        hosting.sizingOptions = []
        panel.contentView = LyricsPanelContainer(hosting: hosting) { [weak self] in self?.onCloseRequested() }
        isPlacing = true
        panel.setFrame(frame, display: false)
        isPlacing = false
        // Before the panel can be shown, so no frame of it is ever recorded against the setting: it stands for a widget under
        // the collapsed notch, which "when collapsed" and "always" keep out of recordings.
        follower = CaptureHidingFollower(panel, as: .compact, interface: interface)
        self.panel = panel
        applySettings()
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.frameChanged() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPresence() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        })
        stopSystemEvents = systemEvents.start { [weak self] event in self?.presence.apply(event) }
        present(panel)
        refreshPresence()
    }

    /// Takes the panel off the screen and lets it go. A move not remembered yet is remembered first.
    func hide() {
        guard let panel else { return }
        if pendingSave != nil { saveFrame() }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        stopSystemEvents?()
        stopSystemEvents = nil
        presence.reset()
        relocationEnd?.cancel()
        relocationEnd = nil
        isRelocating = false
        follower?.stop()
        follower = nil
        self.panel = nil
        panel.orderOut(nil)
        panel.close()
        // The panel is usually closed from its own close button, so its views are let go on the next turn rather than under
        // their own feet.
        Task { panel.contentView = nil }
    }

    /// The setting's opacity (kept within `opacityRange`) and whether the pointer goes through the panel to what is under it.
    func apply(opacity: Double, clickThrough: Bool) {
        self.opacity = min(max(opacity, Self.opacityRange.lowerBound), Self.opacityRange.upperBound)
        self.clickThrough = clickThrough
        applySettings()
    }

    private func applySettings() {
        panel?.alphaValue = opacity
        panel?.ignoresMouseEvents = clickThrough
    }

    /// The panel moved or changed size: remembered once it has stood still for `saveDelay`.
    func frameChanged() {
        guard panel != nil, !isPlacing, !isRelocating else { return }
        pendingSave?.cancel()
        pendingSave = scheduler.schedule(after: Self.saveDelay) { [weak self] in self?.saveFrame() }
    }

    private func saveFrame() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let panel else { return }
        placement.remember(panel.frame, among: displays())
        onPlacementChange(placement)
    }

    private func refreshPresence() {
        guard let panel else { return }
        presence.setWindowVisible(windowIsVisible(panel))
    }

    /// The displays changed while the panel is up: it goes where it belongs on the displays that are there, on the main one when
    /// its own is gone and back on its own when that is back. What the system does to the panel meanwhile, and a move that was
    /// waiting to be remembered, are not the user's choice and are not kept.
    func screensChanged() {
        guard let panel else { return }
        pendingSave?.cancel()
        pendingSave = nil
        isRelocating = true
        relocationEnd?.cancel()
        relocationEnd = scheduler.schedule(after: Self.relocationSettle) { [weak self] in
            self?.isRelocating = false
            self?.relocationEnd = nil
        }
        let frame = placement.restoredFrame(among: displays())
        guard frame != panel.frame else { return }
        isPlacing = true
        panel.setFrame(frame, display: false)
        isPlacing = false
    }
}
