import AppKit
import NotchUI
import SwiftUI

/// What the module needs from the window it puts on the lock screen, so tests can stand in for the real panel.
protocol LockScreenWindow: AnyObject {
    var windowNumber: Int { get }
    /// Whether a click reaches the window. False, the window lets every click through to what is under it.
    var takesClicks: Bool { get set }
    /// Makes the window as tall as a card of `card` points, keeping its top under the notch. The module calls it when the card
    /// changes height (lyric lines appear or go).
    func fit(toCardHeight card: CGFloat)
    func show()
    func dismiss()
}

/// Takes the click that reaches it even though MyNotch is not the active app, which it never is on the lock screen.
final class LockScreenHostingView: NSHostingView<AnyView> {
    /// How tall the card is, at the top of the view. Where the view is taller than the card (a moment after the lyric lines went),
    /// and in the card's rounded corners, nothing is hit, so no click there is the card's. nil until the card is known: the whole
    /// view then.
    var cardHeight: CGFloat?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let cardHeight else { return super.hitTest(point) }
        let local = superview.map { convert(point, from: $0) } ?? point
        let card = CGRect(x: 0, y: isFlipped ? 0 : bounds.height - cardHeight, width: bounds.width, height: cardHeight)
        let radius = min(LockScreenRootView.cornerRadius, card.width / 2, card.height / 2)
        guard CGPath(roundedRect: card, cornerWidth: radius, cornerHeight: radius, transform: nil).contains(local) else { return nil }
        return super.hitTest(point)
    }
}

/// A small panel under the notch, as tall as the card it shows (so with lyric lines it is taller), which leaves no strip of it
/// that could take a click the card does not want. It lets clicks through until `takesClicks` is set, which the module does only
/// while a view with buttons is shown and the user allows them. It never takes the keyboard and never activates MyNotch,
/// because on the lock screen it must not be able to steal anything from the password field.
///
/// It follows the user's hide-from-recording setting like the notch's own panels, as a widget under the collapsed
/// notch: "when collapsed" and "always" keep it out of recordings and shared screens, "never" leaves it in.
final class LockScreenPanel: NSPanel, LockScreenWindow {
    static let width: CGFloat = 340
    static let minimumHeight = LockScreenRootView.minimumHeight
    /// A card taller than this (a view that is not Media's) is cut at it rather than growing without limit.
    static let maximumHeight: CGFloat = 160
    /// Space between the notch and the panel.
    static let gap: CGFloat = 8

    /// How tall the panel is for a card of `card` points: as tall as the card, rounded up so that it is never clipped, and within
    /// the card's own minimum and `maximumHeight`. About 65 for the cover row, bar and padding, and about 105 with the lyric lines.
    static func height(forCard card: CGFloat) -> CGFloat {
        guard !card.isNaN else { return minimumHeight }
        return min(max(ceil(card - 0.01), minimumHeight), maximumHeight)
    }

    /// Top centre of `screen`, `gap` under the notch as it is drawn there (AppKit coordinates), `height` tall. The notch is the
    /// hardware one, or on a display without one the virtual notch of the user's settings: as tall as they say, and a floating pill that
    /// hangs `topGap` below the edge as well as one stuck to it. Every notch is laid out from one config, so any notch that is showing
    /// tells it; with none showing (the user hid it) the defaults are what is left to go by.
    static func frame(on screen: ScreenDescriptor, height: CGFloat, interface: NotchInterface = .shared) -> CGRect {
        let geometry = NotchGeometry(screen: screen, config: interface.notches.first?.geometry.config ?? NotchLayoutConfig())
        return CGRect(
            x: screen.frame.midX + geometry.centerOffset - width / 2,
            y: screen.frame.maxY - geometry.topGap - geometry.notchSize.height - gap - height,
            width: width,
            height: height
        )
    }

    /// How tall the card `content` draws is at the panel's width, measured in a hosting view that is thrown away, so that the panel
    /// is made the right height and a card with lyric lines is never shown clipped first.
    static func cardHeight(of content: AnyView) -> CGFloat {
        NSHostingView(rootView: content.frame(width: width)).fittingSize.height
    }

    /// A panel on the main screen (the one with the menu bar), or nil when there is no screen.
    static func make(content: AnyView) -> (any LockScreenWindow)? {
        guard let screen = NSScreen.screens.first else { return nil }
        let height = height(forCard: cardHeight(of: content))
        return LockScreenPanel(frame: frame(on: ScreenDescriptor(screen), height: height), content: content)
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
        let hosting = LockScreenHostingView(rootView: content)
        // The panel is sized to the card by `fit(toCardHeight:)`, not by SwiftUI.
        hosting.sizingOptions = []
        hosting.cardHeight = frame.height
        contentView = hosting
        // Before the panel can be shown, so no frame of it is ever recorded against the setting.
        follower = CaptureHidingFollower(self, as: .compact, interface: interface)
    }

    var takesClicks: Bool {
        get { !ignoresMouseEvents }
        set { ignoresMouseEvents = !newValue }
    }

    func fit(toCardHeight card: CGFloat) {
        let height = Self.height(forCard: card)
        (contentView as? LockScreenHostingView)?.cardHeight = height
        guard abs(height - frame.height) >= 0.5 else { return }
        // The top stays where it is, under the notch: AppKit's origin is the bottom, so it moves.
        setFrame(CGRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height), display: false)
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
