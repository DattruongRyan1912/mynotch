import AppKit
import SwiftUI

/// Borderless, non-activating panel that floats above the menu bar on every Space.
final class NotchPanel: NSPanel {
    init(frame: CGRect) {
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

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func resignKey() {
        super.resignKey()
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
