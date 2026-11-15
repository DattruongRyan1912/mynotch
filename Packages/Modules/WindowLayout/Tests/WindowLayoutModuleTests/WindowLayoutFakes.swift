import CoreGraphics
@testable import WindowLayoutModule

/// A window that records what it was asked, so no real window is ever moved. Frames are in Accessibility coordinates.
/// Like a real app it can keep a smallest or a largest size whatever it is asked for, apply a size a moment late, stop
/// answering, be hidden and be closed.
final class FakeWindow: SnapWindow {
    var current: CGRect?
    let app: SnapApp
    /// The smallest and the largest size the app lets the window have.
    var minimum: CGSize
    var maximum: CGSize?
    private(set) var placements: [SnapPlacement] = []
    /// Where the zones were, one per placement asked for.
    var setFrames: [CGRect] { placements.map(\.frame) }
    /// What `place` answers: an app that refuses to be moved.
    var accepts = true
    /// An app that stops answering about the window once it has been moved.
    var goesSilentOnceMoved = false
    /// A slow app: the window is moved at once but keeps its old size until it has been asked about it once.
    var appliesSizeLate = false
    /// The app had its enhanced user interface on, which the placement switched off for the move.
    var enhancedUI = false
    /// The window is minimised or its app is hidden.
    var isHidden = false
    /// How often the module asked whether the window is out of sight.
    private(set) var outOfSightChecks = 0
    private var settled: CGRect?

    init(
        frame: CGRect? = CGRect(x: 100, y: 100, width: 800, height: 600),
        app: SnapApp = SnapApp(bundleID: "com.example.fake", name: "Fake"), minimum: CGSize = .zero
    ) {
        current = frame
        self.app = app
        self.minimum = minimum
    }

    var isOutOfSight: Bool {
        outOfSightChecks += 1
        return isHidden
    }

    func frame() -> CGRect? {
        defer {
            if let settled {
                current = settled
                self.settled = nil
            }
        }
        return current
    }

    func place(_ placement: SnapPlacement) -> SnapOutcome {
        placements.append(placement)
        guard accepts else { return SnapOutcome(moved: false, enhancedUI: enhancedUI) }
        var size = CGSize(width: max(placement.frame.width, minimum.width), height: max(placement.frame.height, minimum.height))
        if let maximum { size = CGSize(width: min(size.width, maximum.width), height: min(size.height, maximum.height)) }
        let final = CGRect(origin: placement.origin(for: size), size: size)
        if goesSilentOnceMoved {
            current = nil
        } else if appliesSizeLate, let old = current {
            current = CGRect(origin: final.origin, size: old.size)
            settled = final
        } else {
            current = final
        }
        return SnapOutcome(moved: true, enhancedUI: enhancedUI)
    }

    func isSame(as other: any SnapWindow) -> Bool { other === self }

    /// The user dragging the window: it moves, its size stays.
    func drag(to origin: CGPoint) {
        guard let frame = current else { return }
        current = CGRect(origin: origin, size: frame.size)
    }

    /// The user closing the window: the app no longer answers for it.
    func close() { current = nil }
}

/// Answers `focusedWindow` from a script and counts how often it was asked.
final class FakeWindowProbe: WindowProbe {
    var focused: (any SnapWindow)?
    private(set) var asked = 0

    init(_ focused: (any SnapWindow)? = nil) {
        self.focused = focused
    }

    func focusedWindow() -> (any SnapWindow)? {
        asked += 1
        return focused
    }
}

/// Stands in for the system's mouse and key monitors: tests send the events themselves.
final class FakeDragEvents: DragEventSource {
    private var handler: (@MainActor (DragEvent) -> Void)?
    private(set) var isStarted = false
    private(set) var watchingEscape = false
    private(set) var escapeChanges: [Bool] = []

    func start(_ handler: @escaping @MainActor (DragEvent) -> Void) {
        self.handler = handler
        isStarted = true
    }

    func stop() {
        handler = nil
        isStarted = false
        watchingEscape = false
    }

    func setWatchingEscape(_ watching: Bool) {
        guard watching != watchingEscape else { return }
        watchingEscape = watching
        escapeChanges.append(watching)
    }

    func send(_ event: DragEvent) {
        handler?(event)
    }
}

/// Records where the preview would be, without a window.
final class FakePreview: SnapPreview {
    private(set) var frame: CGRect?
    private(set) var shown: [CGRect] = []
    private(set) var hides = 0
    private(set) var isDismissed = false

    var isVisible: Bool { frame != nil }

    func show(frame: CGRect) {
        self.frame = frame
        shown.append(frame)
    }

    func hide() {
        frame = nil
        hides += 1
    }

    func dismiss() {
        frame = nil
        isDismissed = true
    }
}


/// A window's Accessibility attributes with the habits of real apps: a window that has a smallest size or a largest size
/// keeps it whatever it is told, a fixed-size window refuses a size, and an app may refuse to move. Every write is
/// recorded in order, so tests also see how many calls into the app were made.
final class FakeWindowAttributes: WindowAttributes {
    var origin: CGPoint
    private(set) var windowSize: CGSize
    var minimum = CGSize.zero
    var maximum: CGSize?
    /// A fixed-size window: the app answers that it cannot be resized.
    var isResizable = true
    var isMovable = true
    /// The room of the display the window is on until it has been moved: apps clamp a size to it, so a window placed on a
    /// larger display only gets its size once it is there.
    var sizeLimitUntilMoved: CGSize?
    var canReadSize = true
    /// The app's enhanced user interface: nil for an app that has none (most of them), true for Chrome with the mode on.
    var enhancedUI: Bool?
    /// An app that does not let the switch be changed.
    var canSetEnhancedUI = true
    /// What an app does with a move while the mode is on, as Chrome does: says yes and does nothing (or animates it).
    var ignoresMovesWhileEnhanced = true
    private var hasMoved = false
    /// The size and position writes only, in order.
    private(set) var calls: [String] = []
    /// What was written to the switch, in order.
    private(set) var enhancedWrites: [Bool] = []
    /// Every write of every kind, in order: `enhanced=false`, `size`, `position`, `enhanced=true`.
    private(set) var timeline: [String] = []

    init(frame: CGRect = CGRect(x: 100, y: 100, width: 800, height: 600)) {
        origin = frame.origin
        windowSize = frame.size
    }

    var frame: CGRect { CGRect(origin: origin, size: windowSize) }

    func position() -> CGPoint? { origin }

    func size() -> CGSize? { canReadSize ? windowSize : nil }

    func enhancedUserInterface() -> Bool? { enhancedUI }

    func setEnhancedUserInterface(_ on: Bool) -> Bool {
        enhancedWrites.append(on)
        timeline.append("enhanced=\(on)")
        guard canSetEnhancedUI else { return false }
        enhancedUI = on
        return true
    }

    private var ignoresMoves: Bool { enhancedUI == true && ignoresMovesWhileEnhanced }

    func setPosition(_ position: CGPoint) -> Bool {
        calls.append("position")
        timeline.append("position")
        guard isMovable else { return false }
        guard !ignoresMoves else { return true }
        origin = position
        hasMoved = true
        return true
    }

    func setSize(_ requested: CGSize) -> Bool {
        calls.append("size")
        timeline.append("size")
        guard isResizable else { return false }
        guard !ignoresMoves else { return true }
        var granted = CGSize(width: max(requested.width, minimum.width), height: max(requested.height, minimum.height))
        if let maximum { granted = CGSize(width: min(granted.width, maximum.width), height: min(granted.height, maximum.height)) }
        if !hasMoved, let limit = sizeLimitUntilMoved {
            granted = CGSize(width: max(min(granted.width, limit.width), minimum.width), height: max(min(granted.height, limit.height), minimum.height))
        }
        windowSize = granted
        return true
    }
}
