import AppKit
import NotchUI
import SwiftUI

/// Watches for a click anywhere but the preview. A value of two closures, so tests install a recorder instead of real event
/// monitors. Mouse monitors need no Accessibility permission.
struct ClipboardPreviewClickMonitor {
    /// Starts watching and returns what `stop` needs; nil when AppKit refused. `handler` gets the identity of the window that
    /// was clicked (nil for a click in another app) and answers whether the click is swallowed: a click in one of MyNotch's own
    /// windows that closes the preview must not also press the card or row under it.
    var start: (@escaping @MainActor @Sendable (ObjectIdentifier?) -> Bool) -> Any?
    var stop: (Any) -> Void

    static let system = ClipboardPreviewClickMonitor(
        start: { handler in
            let buttons: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            // Clicks in other apps are only observed; clicks in MyNotch's windows come to the local monitor, which can eat them.
            let global = NSEvent.addGlobalMonitorForEvents(matching: buttons) { _ in
                MainActor.assumeIsolated { _ = handler(nil) }
            }
            let local = NSEvent.addLocalMonitorForEvents(matching: buttons) { event in
                let window = event.window.map(ObjectIdentifier.init)
                let swallowed = MainActor.assumeIsolated { handler(window) }
                return swallowed ? nil : event
            }
            return [global, local].compactMap { $0 }
        },
        stop: { token in
            for monitor in token as? [Any] ?? [] { NSEvent.removeMonitor(monitor) }
        }
    )
}

/// A big, quiet window for the large preview: borderless, non-activating and never key, so showing it moves no keyboard
/// focus, leaves "no window of MyNotch has the keyboard" true for a paste from the pinned panel, and gives the click-outside
/// monitors nothing to trip over. It cannot take Esc either, which stays with the window the preview belongs to.
final class ClipboardPreviewPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        // Above the floating panel and the library window, which it belongs to.
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        title = "Xem trước"
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosts the preview in a `ClipboardPreviewPanel`. One at a time, made when it opens and dropped when it closes, so a closed
/// preview holds nothing of what it showed (an item of a locked board that has just locked is gone with it).
final class ClipboardPreviewController: NSObject, ClipboardPreviewWindowing {
    static let cornerRadius: CGFloat = 14

    private let interface: NotchInterface
    private let screens: () -> [ClipboardPanelPlacement.Screen]
    private let clickMonitor: ClipboardPreviewClickMonitor
    private let center: NotificationCenter
    private let orderFront: (ClipboardPreviewPanel) -> Void
    private var panel: ClipboardPreviewPanel?
    private var onOutsideClick: (() -> Void)?
    /// Keeps it out of recordings the way the user asked, while it exists.
    private var captureFollower: CaptureHidingFollower?
    private var clickToken: Any?
    private var resignObserver: (any NSObjectProtocol)?

    var isOpen: Bool { panel != nil }

    /// `interface` is where the "hide from screen recording" setting comes from: the app's shared one, or a test's own.
    /// `orderFront` is what puts the panel on the screen, so a test can leave it off.
    init(
        interface: NotchInterface = .shared,
        screens: @escaping () -> [ClipboardPanelPlacement.Screen] = {
            NSScreen.screens.map { ClipboardPanelPlacement.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        },
        clickMonitor: ClipboardPreviewClickMonitor = .system,
        center: NotificationCenter = .default,
        orderFront: @escaping (ClipboardPreviewPanel) -> Void = { $0.orderFrontRegardless() }
    ) {
        self.interface = interface
        self.screens = screens
        self.clickMonitor = clickMonitor
        self.center = center
        self.orderFront = orderFront
    }

    func show(_ content: AnyView, hostFrame: CGRect?, onOutsideClick: @escaping () -> Void) {
        close()
        guard let frame = ClipboardPreviewPlacement.frame(host: hostFrame, screens: screens()) else { return }
        let panel = makePanel(frame: frame)
        panel.contentView = makeContentView(content, size: frame.size)
        self.panel = panel
        self.onOutsideClick = onOutsideClick
        watch()
        // Never `makeKey`: the keyboard stays where it was.
        orderFront(panel)
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        onOutsideClick = nil
        stopWatching()
        stopFollowingSetting()
        panel.orderOut(nil)
        // The preview is usually closed from inside an event handler of the window it belongs to, so its views are let go on
        // the next turn rather than under their own feet.
        Task { panel.contentView = nil }
    }

    /// A panel that is not on any screen yet, already hidden from recordings when the setting says so and kept that way while it
    /// exists. The user opens a preview, like an open notch, so "only while collapsed" shows it.
    func makePanel(frame: CGRect) -> ClipboardPreviewPanel {
        let panel = ClipboardPreviewPanel(frame: frame)
        captureFollower?.stop()
        captureFollower = CaptureHidingFollower(panel, as: .toast, interface: interface)
        return panel
    }

    func stopFollowingSetting() {
        captureFollower?.stop()
        captureFollower = nil
    }

    // MARK: Private

    /// A click anywhere but the preview, or the application losing the front (the library's window going behind another app).
    private func watch() {
        stopWatching()
        clickToken = clickMonitor.start { [weak self] window in
            guard let self, let panel = self.panel, window != ObjectIdentifier(panel) else { return false }
            self.outside()
            return window != nil
        }
        resignObserver = center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.outside() }
        }
    }

    private func outside() {
        guard let onOutsideClick else { return }
        onOutsideClick()
    }

    private func stopWatching() {
        if let clickToken { clickMonitor.stop(clickToken) }
        clickToken = nil
        if let resignObserver { center.removeObserver(resignObserver) }
        resignObserver = nil
    }

    func makeContentView(_ content: AnyView, size: CGSize) -> NSView {
        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        background.material = .popover
        background.blendingMode = .behindWindow
        // An inactive app's blur would otherwise go flat.
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = Self.cornerRadius
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        // Outside the notch's views, so it is given the notch's accent here. It takes the first click: the panel is never key, so
        // every click on it is a first one.
        let hosting = ClipboardFirstMouseHostingView(rootView: ClipboardAccentHost(interface: interface) { content })
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)
        return background
    }
}
