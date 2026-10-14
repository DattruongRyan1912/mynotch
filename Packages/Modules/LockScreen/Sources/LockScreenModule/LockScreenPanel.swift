import AppKit
import NotchUI
import SwiftUI

/// What the module needs from the window it puts on the lock screen, so tests can stand in for the real panel.
protocol LockScreenWindow: AnyObject {
    var windowNumber: Int { get }
    func show()
    func dismiss()
}

/// A small, click-through panel under the notch. It never takes the keyboard or activates MyNotch,
/// because on the lock screen it must not be able to steal anything from the password field.
///
/// It follows the user's hide-from-recording setting like the notch's own panels, as a widget under the collapsed
/// notch: "when collapsed" and "always" keep it out of recordings and shared screens, "never" leaves it in.
final class LockScreenPanel: NSPanel, LockScreenWindow {
    static let size = CGSize(width: 300, height: 80)
    /// Space between the notch and the panel.
    static let gap: CGFloat = 8

    /// Top centre of `screen`, just under the notch (AppKit coordinates).
    static func frame(on screen: ScreenDescriptor) -> CGRect {
        let geometry = NotchGeometry(screen: screen, config: NotchLayoutConfig())
        return CGRect(
            x: screen.frame.midX + geometry.centerOffset - size.width / 2,
            y: screen.frame.maxY - geometry.notchSize.height - gap - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// A panel on the main screen (the one with the menu bar), or nil when there is no screen.
    static func make(content: AnyView) -> (any LockScreenWindow)? {
        guard let screen = NSScreen.screens.first else { return nil }
        return LockScreenPanel(frame: frame(on: ScreenDescriptor(screen)), content: content)
    }

    private var follower: CaptureHidingFollower?

    /// `interface` is where the setting comes from: the app's shared one, or a test's own.
    init(frame: CGRect, content: AnyView, interface: NotchInterface = .shared) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        contentView = NSHostingView(rootView: content)
        // Before the panel can be shown, so no frame of it is ever recorded against the setting.
        follower = CaptureHidingFollower(self, as: .compact, interface: interface)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        orderFrontRegardless()
    }

    func dismiss() {
        follower?.stop()
        follower = nil
        orderOut(nil)
        close()
    }
}
