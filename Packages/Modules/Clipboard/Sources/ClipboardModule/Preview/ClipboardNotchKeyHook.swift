import AppKit
import SwiftUI

/// Watches the key presses of the notch's window. A value of two closures, so tests install a recorder instead of a real event
/// monitor. A local monitor sees a key press before the window does, which is what Space needs: in the search field it is typed text
/// and never reaches it as a command, and the notch's window is not ours to subclass.
struct ClipboardPreviewKeyMonitor {
    /// Starts watching and returns what `stop` needs; nil when AppKit refused. `handler` answers whether the key was taken.
    var start: (@escaping @MainActor (NSEvent) -> Bool) -> Any?
    var stop: (Any) -> Void

    static let system = ClipboardPreviewKeyMonitor(
        start: { handler in
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // The event only crosses to the main actor for the length of the call.
                nonisolated(unsafe) let unsafeEvent = event
                let taken = MainActor.assumeIsolated { handler(unsafeEvent) }
                return taken ? nil : event
            }
        },
        stop: { NSEvent.removeMonitor($0) }
    )
}

/// Gives the notch tab's preview its keys. Placed behind the tab, it finds the notch's window when it is put in it, watches that window's
/// key presses while the tab is shown, and offers each to the model: Space, ⌘Y, Esc, Tab and Return mean something to an open or a
/// closable preview, and anything else goes on to the search field.
///
/// Only a key typed into the tab's search field is offered. A board's name, a password, the board and stack buttons and every other
/// window of MyNotch (the library, Settings, which have fields of their own) are left alone.
struct ClipboardNotchKeyHook: NSViewRepresentable {
    let model: ClipboardTabPreviewModel
    var monitor: ClipboardPreviewKeyMonitor = .system

    func makeNSView(context: Context) -> HookView {
        HookView(model: model, monitor: monitor)
    }

    func updateNSView(_ view: HookView, context: Context) {}

    static func dismantleNSView(_ view: HookView, coordinator: ()) {
        view.stop()
    }

    final class HookView: NSView {
        private let model: ClipboardTabPreviewModel
        private let monitor: ClipboardPreviewKeyMonitor
        private var token: Any?
        /// Which window a key press is for; the event's own, but a test has no window number to give a window it never shows.
        var windowOfEvent: (NSEvent) -> NSWindow? = { $0.window }

        init(model: ClipboardTabPreviewModel, monitor: ClipboardPreviewKeyMonitor) {
            self.model = model
            self.monitor = monitor
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        var isWatching: Bool { token != nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            model.hostWindow = { [weak window] in (window?.frame, window.map(ObjectIdentifier.init)) }
            token = monitor.start { [weak self] event in self?.offer(event) ?? false }
        }

        func stop() {
            if let token { monitor.stop(token) }
            token = nil
            model.hostWindow = { (nil, nil) }
        }

        /// True when the preview took the key press, so the search field never gets it.
        func offer(_ event: NSEvent) -> Bool {
            guard event.type == .keyDown, let window, windowOfEvent(event) === window else { return false }
            // Nothing but the search field is a place to type that the preview watches: no cards take the keyboard in the notch.
            return ClipboardPreviewKeys.offer(event, in: window, to: { [weak model] key, target, marked in
                model?.handlePreviewKey(key, target: target, hasMarkedText: marked) ?? false
            }, isCards: { _ in false })
        }
    }
}
