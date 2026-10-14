import AppKit
import NotchUI
import SwiftUI

/// Hosts the floating panel in an `NSPanel`. One panel at a time, made when it opens and dropped when it closes, so a
/// closed panel holds no views. MyNotch is never activated: the app in front keeps the keyboard focus that ⌘V goes to.
final class ClipboardPanelController: NSObject, ClipboardPanelWindowing {
    static let cornerRadius: CGFloat = 14

    private let captureHiding: () -> CaptureHiding
    private let pointer: () -> CGPoint
    private let screens: () -> [ClipboardPanelPlacement.Screen]
    private var panel: ClipboardFloatingPanel?
    private var keySink: ClipboardKeySinkPanel?
    private var onClose: (() -> Void)?
    /// A click in another app, while the panel is open.
    private var clickMonitor: Any?
    /// Any change of the settings, while the panel is open.
    private var settingsObserver: NSObjectProtocol?

    var isOpen: Bool { panel != nil }

    var isKey: Bool { panel?.isKeyWindow == true }

    var origin: CGPoint? { panel?.frame.origin }

    /// `captureHiding` is the user's "hide from screen recording" setting, read each time it is applied.
    init(
        captureHiding: @escaping () -> CaptureHiding,
        pointer: @escaping () -> CGPoint = { NSEvent.mouseLocation },
        screens: @escaping () -> [ClipboardPanelPlacement.Screen] = {
            NSScreen.screens.map { ClipboardPanelPlacement.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        }
    ) {
        self.captureHiding = captureHiding
        self.pointer = pointer
        self.screens = screens
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
        panel.onCancel = { [weak model] in model?.requestClose() }
        panel.onResignKey = { [weak model] in model?.focusLost() }
        panel.onBecomeKey = { [weak self, weak panel] in
            if let panel { self?.applyCaptureHiding(to: panel) }
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
    /// without the visible panel blinking.
    func returnKeyboard() {
        guard let panel, panel.isKeyWindow else { return }
        let sink = keySink ?? ClipboardKeySinkPanel()
        keySink = sink
        // Inside the panel at its top edge, where nothing can be seen of a clear 1 pt window.
        sink.setFrame(CGRect(x: panel.frame.midX - 0.5, y: panel.frame.maxY - 1, width: 1, height: 1), display: false)
        sink.orderFrontRegardless()
        sink.makeKey()
        sink.orderOut(nil)
    }

    func close() {
        guard let panel else { return }
        self.panel = nil
        stopWatching()
        // Before leaving the screen, so its own resigning is not taken for the user clicking elsewhere.
        panel.onQuickPick = nil
        panel.onCancel = nil
        panel.onBecomeKey = nil
        panel.onResignKey = nil
        panel.orderOut(nil)
        // Dropping the content ends the panel's views at once and frees its thumbnails.
        panel.contentView = nil
        keySink?.orderOut(nil)
        keySink = nil
        let onClose = onClose
        self.onClose = nil
        onClose?()
    }

    /// A panel that is not on any screen yet, already hidden from recordings when the setting says so: there is no
    /// frame in which a recorder could see it.
    func makePanel() -> ClipboardFloatingPanel {
        let panel = ClipboardFloatingPanel(size: ClipboardPanelPlacement.size)
        applyCaptureHiding(to: panel)
        return panel
    }

    /// The same rule as the notch's panels. The panel only exists while the user has it open, which is when the notch is
    /// expanded, so "only while collapsed" shows it.
    func applyCaptureHiding(to panel: NSPanel) {
        let type = captureHiding().sharingType(for: .open(nil))
        if panel.sharingType != type { panel.sharingType = type }
    }

    // MARK: Private

    private func makeContentView(_ content: AnyView, size: CGSize) -> NSView {
        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        background.material = .popover
        background.blendingMode = .behindWindow
        // An inactive app's blur would otherwise go flat.
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = Self.cornerRadius
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        let hosting = ClipboardFirstMouseHostingView(rootView: content)
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)
        return background
    }

    /// A click in another app means the user is done with an unpinned panel, even when no key status moves (the app in
    /// front was already the active one). Mouse monitors need no Accessibility permission.
    private func watch(_ model: ClipboardPanelModel) {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak model] _ in
            MainActor.assumeIsolated { model?.focusLost() }
        })
        // A pinned panel stays on screen while Settings changes the capture setting.
        settingsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let panel = self?.panel { self?.applyCaptureHiding(to: panel) }
            }
        }
    }

    private func stopWatching() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        settingsObserver = nil
    }
}
