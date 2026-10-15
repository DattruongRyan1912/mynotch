import AppKit
import NotchUI
import SwiftUI

/// Watches clicks in other apps while the panel is open. A value of two closures, so tests install a recorder instead of
/// a real event monitor. Mouse monitors need no Accessibility permission.
struct ClipboardPanelClickMonitor {
    /// Starts watching and returns what `stop` needs; nil when AppKit refused. `handler` runs on the main actor.
    var start: (@escaping @MainActor @Sendable () -> Void) -> Any?
    var stop: (Any) -> Void

    static let system = ClipboardPanelClickMonitor(
        start: { handler in
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in
                MainActor.assumeIsolated { handler() }
            }
        },
        stop: { NSEvent.removeMonitor($0) }
    )
}

/// Hosts the floating panel in an `NSPanel`. One panel at a time, made when it opens and dropped when it closes, so a
/// closed panel holds no views. MyNotch is never activated: the app in front keeps the keyboard focus that ⌘V goes to.
final class ClipboardPanelController: NSObject, ClipboardPanelWindowing {
    static let cornerRadius: CGFloat = 14

    private let interface: NotchInterface
    private let pointer: () -> CGPoint
    private let screens: () -> [ClipboardPanelPlacement.Screen]
    private let clickMonitor: ClipboardPanelClickMonitor
    private let keyboardHandBack = KeyboardHandBack()
    private var panel: ClipboardFloatingPanel?
    private var onClose: (() -> Void)?
    /// Keeps the panel out of recordings the way the user asked, while it exists.
    private var captureFollower: CaptureHidingFollower?
    /// The click monitor's token, while the panel is open.
    private var clickToken: Any?

    var isOpen: Bool { panel != nil }

    var isKey: Bool { panel?.isKeyWindow == true }

    var origin: CGPoint? { panel?.frame.origin }

    var frame: CGRect? { panel?.frame }

    var windowIdentity: ObjectIdentifier? { panel.map(ObjectIdentifier.init) }

    /// `interface` is where the "hide from screen recording" setting comes from: the app's shared one, or a test's own.
    init(
        interface: NotchInterface = .shared,
        pointer: @escaping () -> CGPoint = { NSEvent.mouseLocation },
        screens: @escaping () -> [ClipboardPanelPlacement.Screen] = {
            NSScreen.screens.map { ClipboardPanelPlacement.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        },
        clickMonitor: ClipboardPanelClickMonitor = .system
    ) {
        self.interface = interface
        self.pointer = pointer
        self.screens = screens
        self.clickMonitor = clickMonitor
    }

    func show(_ content: AnyView, model: ClipboardPanelModel, restoringOrigin: CGPoint?, onClose: @escaping () -> Void) {
        guard panel == nil else {
            focus()
            return
        }
        let size = ClipboardPanelPlacement.size
        let panel = makePanel()
        panel.contentView = makeContentView(content, size: size)
        let screens = screens()
        let frame = restoringOrigin.flatMap { ClipboardPanelPlacement.restoredFrame(size: size, origin: $0, screens: screens) }
            ?? ClipboardPanelPlacement.frame(size: size, pointer: pointer(), screens: screens)
        panel.setFrame(frame, display: false)
        panel.onQuickPick = { [weak model] in model?.pick(number: $0) ?? false }
        panel.onCancel = { [weak model] in model?.cancel() }
        panel.onResignKey = { [weak model] in model?.focusLost() }
        panel.onPreviewKey = { [weak model] key, target, marked in
            model?.handlePreviewKey(key, target: target, hasMarkedText: marked) ?? false
        }
        self.panel = panel
        self.onClose = onClose
        watch(model)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func focus() {
        panel?.orderFrontRegardless()
        panel?.makeKey()
    }

    /// Hands key status to a hidden 1 pt panel and orders that one out, which returns the keyboard to the app in front
    /// without the visible panel blinking (NotchUI's hand-back, the one the notch uses). A panel that is not key has
    /// nothing to hand back; the answer is then whether the keyboard is with the app in front anyway.
    func returnKeyboard() -> Bool {
        let front = NSWorkspace.shared.frontmostApplication
        guard let panel, panel.isKeyWindow else { return KeyboardHandBack.keyboardIsWith(front) }
        return keyboardHandBack.returnKeyboard(from: panel, to: front)
    }

    func keyboardIsWithFrontApp() -> Bool {
        KeyboardHandBack.keyboardIsWith(NSWorkspace.shared.frontmostApplication)
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        stopWatching()
        stopFollowingSetting()
        keyboardHandBack.close()
        // Before leaving the screen, so its own resigning is not taken for the user clicking elsewhere.
        panel.onQuickPick = nil
        panel.onCancel = nil
        panel.onResignKey = nil
        panel.onPreviewKey = nil
        // Off the screen at once: the keyboard goes back to the app in front before ⌘V is sent.
        panel.orderOut(nil)
        // The panel is usually closed from inside one of its own event handlers (Return in the field, a click on a row,
        // ⌘N), so its views are let go on the next turn rather than under their own feet.
        Task { panel.contentView = nil }
        let onClose = onClose
        self.onClose = nil
        onClose?()
    }

    /// A panel that is not on any screen yet, already hidden from recordings when the setting says so (there is no frame
    /// in which a recorder could see it) and kept that way while it exists. The panel only exists while the user has it
    /// open, which is when the notch is expanded, so "only while collapsed" shows it.
    func makePanel() -> ClipboardFloatingPanel {
        let panel = ClipboardFloatingPanel(size: ClipboardPanelPlacement.size)
        captureFollower?.stop()
        captureFollower = CaptureHidingFollower(panel, as: .toast, interface: interface)
        return panel
    }

    func stopFollowingSetting() {
        captureFollower?.stop()
        captureFollower = nil
    }

    /// A click in another app means the user is done with an unpinned panel, even when no key status moves (the app in
    /// front was already the active one).
    func watch(_ model: ClipboardPanelModel) {
        stopWatching()
        clickToken = clickMonitor.start { [weak model] in model?.focusLost() }
    }

    func stopWatching() {
        if let clickToken { clickMonitor.stop(clickToken) }
        clickToken = nil
    }

    // MARK: Private

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
        // The panel is outside the notch's views, so it is given the notch's accent here.
        let hosting = ClipboardFirstMouseHostingView(rootView: ClipboardAccentHost(interface: interface) { content })
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)
        return background
    }
}
