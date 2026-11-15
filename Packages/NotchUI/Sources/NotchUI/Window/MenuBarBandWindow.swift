import AppKit

/// The black menu bar of one display: a black window over exactly the menu bar's rectangle, so that the transparent menu bar of macOS 26
/// reads as solid black and a MacBook's notch stops being a hole in it.
///
/// The level is `.mainMenu - 1`, one below the menu bar. The menu bar, its items and the status items (`.statusBar`, above it) are drawn
/// over the black; so is the notch's own panel (`.mainMenu + 3`), which a black or glass notch sits in. Everything an app has (normal,
/// floating, modal panels) is below it, and that is safe only because macOS keeps those windows out of the band while the menu bar is
/// shown. The two times it does not (the menu bar auto-hidden, a fullscreen app) are the two times the band is taken away
/// (`MenuBarBand.plan`).
///
/// It follows the user's hide-from-recording setting like the notch's own panels, as a widget under the collapsed notch does:
/// "when collapsed" and "always" keep it out of recordings and shared screens, "never" leaves it in. Menu bar text stays readable
/// because macOS draws light items over a dark bar; the system decides that, nothing here forces it.
final class MenuBarBandWindow: NSPanel {
    static let level = NSWindow.Level.mainMenu - 1

    private var follower: CaptureHidingFollower?

    /// `interface` is where the setting comes from: the app's shared one, or a test's own.
    init(frame: CGRect, interface: NotchInterface = .shared) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        level = Self.level
        // On every Space and stationary, so it stays put through Mission Control and Space changes. Not `.fullScreenAuxiliary`, which
        // is what would let it into the Space of a fullscreen app, where the menu bar is hidden.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovable = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        // NSPanel hides on deactivate by default; Settings activates the app, so leaving it would take the band away every time.
        hidesOnDeactivate = false
        // Hiding MyNotch (⌘H, while Settings is open) hides its windows; the band is the system's menu bar, not MyNotch's.
        canHide = false
        animationBehavior = .none
        // Before the window can be shown, so no frame of it is ever recorded against the setting.
        follower = CaptureHidingFollower(self, as: .compact, interface: interface)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func close() {
        follower?.stop()
        follower = nil
        super.close()
    }
}
