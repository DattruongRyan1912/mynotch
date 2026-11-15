import AppKit
import SwiftUI

/// A small window that downloads a language pack. Translation only offers its download sheet to SwiftUI views,
/// and the sheet may not show for an accessory app, so like Settings the app turns regular (Dock icon, ⌘Tab)
/// while the window is open.
final class LanguageInstallerWindow: NSObject, LanguageInstalling {
    private let status: (LanguagePair) async -> PairStatus
    private var window: NSWindow?

    init(status: @escaping (LanguagePair) async -> PairStatus) {
        self.status = status
    }

    func install(_ pair: LanguagePair, onStatusChange: @escaping @MainActor () -> Void) {
        // One installer at a time: a new pair replaces the window's content.
        let status = status
        let view = LanguageInstallerView(
            pair: pair,
            status: { await status(pair) },
            onStatusChange: onStatusChange,
            close: { [weak self] in self?.window?.close() }
        )
        let window = window ?? makeWindow()
        let controller = NSHostingController(rootView: view)
        window.contentViewController = controller
        window.setContentSize(controller.view.fittingSize)
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Cài gói ngôn ngữ"
        window.isReleasedWhenClosed = false
        // Set once: the window is reused, so it never registers a second close handler.
        window.delegate = self
        return window
    }
}

extension LanguageInstallerWindow: NSWindowDelegate {
    /// Back to a menu bar app, unless another titled window (Settings) still needs the Dock icon, which a minimized
    /// window does too: the Dock is the way back to it.
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        // Dropping the content ends the view's status polling.
        closing.contentViewController = nil
        let othersShown = NSApp.windows.contains {
            $0 !== closing && ($0.isVisible || $0.isMiniaturized) && $0.styleMask.contains(.titled)
        }
        if !othersShown { NSApp.setActivationPolicy(.accessory) }
    }
}
