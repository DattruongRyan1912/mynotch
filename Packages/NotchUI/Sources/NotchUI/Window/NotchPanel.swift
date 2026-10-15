import AppKit
import SwiftUI

/// Borderless, non-activating panel that floats above the menu bar on every Space.
final class NotchPanel: NSPanel {
    /// Where the notifications that make AppKit take the key appearance back are heard (see `activeGlass`); AppKit posts them to the
    /// default center, and a test gives the panel a center of its own, so that the notifications it posts are not heard by a panel of
    /// another test running beside it.
    private let notifications: NotificationCenter

    init(frame: CGRect, notifications: NotificationCenter = .default) {
        self.notifications = notifications
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .mainMenu + 3
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        // The app is never active, so tooltips (e.g. tab names) must be allowed while inactive.
        allowsToolTipsWhenApplicationIsInactive = true
        // NSPanel hides on deactivate by default; Settings activates the app, so leaving it would hide every notch.
        hidesOnDeactivate = false
        // Ordering the panel in or out (fullscreen, display mode) must never play the
        // system's window fade: the notch pops, it does not blink.
        animationBehavior = .none
    }

    /// True only while an open tab accepts keyboard input; the panel never takes the keyboard otherwise.
    var allowsKeyStatus = false
    override var canBecomeKey: Bool { allowsKeyStatus }
    override var canBecomeMain: Bool { false }

    /// Esc (or ⌘.) that no view in the tab handled.
    var onCancel: (() -> Void)?
    /// Called after key status moved to another window, e.g. the user clicked into another app.
    var onResignKey: (() -> Void)?

    /// When set, the panel's glass is drawn as an active window's, whether or not the panel is key (the debug switch
    /// `debug.glass.active`), and nil, the usual, hooks nothing. It never touches key status. Setting it gives the panel the
    /// appearance and keeps it there; setting it back to nil takes it away unless the panel is key.
    var activeGlass: ActiveGlassAppearance? {
        didSet {
            guard activeGlass != oldValue else { return }
            observers.forEach(notifications.removeObserver)
            observers = []
            if let activeGlass {
                observers = Self.resets.map { name in
                    notifications.addObserver(forName: name.0, object: name.1 ? self : nil, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.refreshActiveGlass(afterAppKitHasFinished: true) }
                    }
                }
                activeGlass.acquire(on: self)
            } else {
                oldValue?.release(on: self)
            }
        }
    }

    private var observers: [any NSObjectProtocol] = []

    /// What makes AppKit take the key appearance back: the panel resigning key, the app activating or deactivating (Settings does),
    /// the panel changing screen or what hides it. The flag says whether it is this panel's own notification.
    private static let resets: [(Notification.Name, Bool)] = [
        (NSWindow.didResignKeyNotification, true), (NSWindow.didChangeScreenNotification, true),
        (NSWindow.didChangeOcclusionStateNotification, true), (NSApplication.didBecomeActiveNotification, false),
        (NSApplication.didResignActiveNotification, false),
    ]

    isolated deinit {
        observers.forEach(notifications.removeObserver)
    }

    /// Gives the panel the key appearance again, if it is to have it: now, and, since AppKit may take it back just after the change
    /// that triggered this, once more when the run loop turns. Does nothing with `activeGlass` nil.
    func refreshActiveGlass(afterAppKitHasFinished later: Bool = false) {
        guard let activeGlass else { return }
        activeGlass.acquire(on: self)
        guard later else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let current = self.activeGlass else { return }
            current.acquire(on: self)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func resignKey() {
        super.resignKey()
        refreshActiveGlass(afterAppKitHasFinished: true)
        onResignKey?()
    }
}

/// Hosting view that accepts the first click even though the app is not active.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Scroll events no view under the pointer used: the tab bar, empty notch chrome, and content that does not scroll
    /// that way. A scroll view that handles the event (the clipboard carousel) keeps it, so only what is left over can
    /// become a swipe between tabs.
    var onUnusedScroll: ((NSEvent) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onUnusedScroll?(event)
        super.scrollWheel(with: event)
    }

    #if DEBUG
    /// Layout passes of this view alone; `NotchPerf` counts all of them together, which a test in a process that
    /// animates other notches (they run free without a display link) cannot use.
    private(set) var layoutPasses = 0

    /// SwiftUI evaluates and lays out whatever changed inside this pass, so counting them shows how busy the notch is.
    override func layout() {
        NotchPerf.count(.layouts)
        layoutPasses += 1
        super.layout()
    }
    #endif
}
