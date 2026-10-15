import AppKit
import NotchUI
import SwiftUI

/// Hosts each editor in a regular titled window of its own, made when the editor opens and dropped when it closes. While one is open
/// MyNotch is a regular app, because an accessory app's window cannot take typing; like the library it returns to a menu bar app once
/// the last titled window closes. Each window stays out of recordings when the user asks for that, as the notch's windows do.
final class ClipboardEditorWindowController: NSObject, ClipboardEditorWindowing {
    /// What the app does around a window opening and closing, which a test must not do to the process it runs in.
    struct Activation {
        /// MyNotch comes forward as a regular app, so the window can take typing, and the window is put in front.
        var bringForward: @MainActor (NSWindow) -> Void
        /// `window` closed: back to a menu bar app unless another titled window is still there.
        var windowClosed: @MainActor (NSWindow) -> Void

        static let system = Activation(
            bringForward: { window in
                // The policy first, so the app comes forward as a regular app with its menu bar.
                NSApp.setActivationPolicy(.regular)
                NSApp.activate()
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.makeKeyAndOrderFront(nil)
            },
            windowClosed: { NSApp.setActivationPolicy(ClipboardLibraryActivation.policyAfterClosing($0)) }
        )
    }

    private struct Entry {
        let window: ClipboardEditorWindow
        let model: ClipboardEditorModel
        var onClose: (() -> Void)?
    }

    private let interface: NotchInterface
    private let activation: Activation
    private var entries: [UUID: Entry] = [:]
    /// Keeps each window out of recordings the way the user asked, while it exists.
    private var followers: [ObjectIdentifier: CaptureHidingFollower] = [:]

    /// `interface` is where the "hide from screen recording" setting comes from: the app's shared one, or a test's own.
    init(interface: NotchInterface = .shared, activation: Activation = .system) {
        self.interface = interface
        self.activation = activation
    }

    var openCount: Int { entries.count }

    func show(_ content: AnyView, model: ClipboardEditorModel, onClose: @escaping () -> Void) {
        guard entries[model.itemID] == nil else {
            bringToFront(itemID: model.itemID)
            return
        }
        let window = makeWindow(content, model: model)
        window.center()
        register(window, model: model, onClose: onClose)
        bringToFront(itemID: model.itemID)
    }

    /// Makes the window the controller's, so it answers for its closing. Does not show it.
    func register(_ window: ClipboardEditorWindow, model: ClipboardEditorModel, onClose: @escaping () -> Void) {
        window.delegate = self
        entries[model.itemID] = Entry(window: window, model: model, onClose: onClose)
    }

    /// The window, configured but not on any screen, and already hidden from recordings when the setting says so: there is no frame in
    /// which a recorder could see it. The user opens it like an open notch, so "only while collapsed" shows it.
    func makeWindow(_ content: AnyView, model: ClipboardEditorModel) -> ClipboardEditorWindow {
        // The window is outside the notch's views, so it is given the notch's accent here.
        let controller = NSHostingController(rootView: ClipboardAccentHost(interface: interface) { content })
        let window = ClipboardEditorWindow(contentViewController: controller)
        window.title = "Sửa mục clipboard"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 400))
        window.contentMinSize = NSSize(width: 440, height: 280)
        window.isReleasedWhenClosed = false
        window.onCancel = { [weak model] in model?.cancel() }
        followers[ObjectIdentifier(window)] = CaptureHidingFollower(window, as: .toast, interface: interface)
        return window
    }

    /// Stops a window following the setting, as closing it does.
    func stopFollowingSetting(of window: NSWindow) {
        followers.removeValue(forKey: ObjectIdentifier(window))?.stop()
    }

    func bringToFront(itemID: UUID) {
        guard let window = entries[itemID]?.window else { return }
        activation.bringForward(window)
    }

    func close(itemID: UUID) {
        entries[itemID]?.window.close()
    }
}

extension ClipboardEditorWindowController: NSWindowDelegate {
    /// The close button and ⌘W from the menu: asks the model, which asks the user when there are unsaved words.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let entry = entries.values.first(where: { $0.window === sender }) else { return true }
        return entry.model.windowShouldClose()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow,
              let (id, entry) = entries.first(where: { $0.value.window === closing }) else { return }
        entries[id] = nil
        stopFollowingSetting(of: closing)
        (closing as? ClipboardEditorWindow)?.onCancel = nil
        // Dropping the content ends the editor's views at once and lets go of its text.
        closing.contentViewController = nil
        activation.windowClosed(closing)
        entry.onClose?()
    }
}
