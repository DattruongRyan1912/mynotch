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

/// Owns the lyrics panel while it is up: one panel, made when it is shown and let go when it is hidden, so a hidden panel holds
/// no views and costs nothing. It puts the panel where the user left it on each display and remembers where they leave it
/// next, keeps it out of recordings the way the user asked for the notch, and applies the opacity and the click-through setting.
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
    private var placement: LyricsPanelPlacement
    private var opacity = 1.0
    private var clickThrough = false
    private var follower: CaptureHidingFollower?
    private var observers: [NSObjectProtocol] = []
    private var pendingSave: ScheduledAction?
    /// The panel is being put in place, which is not the user moving it.
    private var isPlacing = false
    private(set) var panel: LyricsFloatingPanel?

    var isShown: Bool { panel != nil }

    /// - Parameters:
    ///   - interface: where the "hide from screen recording" setting comes from: the app's shared one, or a test's own.
    ///   - displays: the displays now, the main one first.
    ///   - present: puts the panel on the screen; tests record it instead.
    ///   - onPlacementChange: hears the placement with the new frame in it, to store.
    init(
        interface: NotchInterface = .shared,
        scheduler: any Scheduler,
        placement: LyricsPanelPlacement,
        displays: @escaping @MainActor () -> [PanelDisplay] = LyricsPanelController.screens,
        present: @escaping (NSPanel) -> Void = { $0.orderFrontRegardless() },
        onPlacementChange: @escaping (LyricsPanelPlacement) -> Void
    ) {
        self.interface = interface
        self.scheduler = scheduler
        self.placement = placement
        self.displays = displays
        self.present = present
        self.onPlacementChange = onPlacementChange
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
        panel.contentView = hosting
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
        present(panel)
    }

    /// Takes the panel off the screen and lets it go. A move not remembered yet is remembered first.
    func hide() {
        guard let panel else { return }
        if pendingSave != nil { saveFrame() }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        follower?.stop()
        follower = nil
        self.panel = nil
        panel.orderOut(nil)
        panel.contentView = nil
        panel.close()
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
        guard panel != nil, !isPlacing else { return }
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
}
