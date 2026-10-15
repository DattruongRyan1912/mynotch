import CoreGraphics
@testable import WindowLayoutModule

/// A window that records what it was asked, so no real window is ever moved. Frames are in Accessibility coordinates.
/// Like a real app it can keep a smallest size whatever it is asked for, and it can be closed.
final class FakeWindow: SnapWindow {
    var current: CGRect?
    let app: SnapApp
    /// The smallest size the app lets the window have.
    var minimum: CGSize
    private(set) var placements: [SnapPlacement] = []
    /// Where the zones were, one per placement asked for.
    var setFrames: [CGRect] { placements.map(\.frame) }
    /// What `place` answers: an app that refuses to be moved.
    var accepts = true
    /// An app that stops answering about the window once it has been moved.
    var goesSilentOnceMoved = false

    init(
        frame: CGRect? = CGRect(x: 100, y: 100, width: 800, height: 600),
        app: SnapApp = SnapApp(bundleID: "com.example.fake", name: "Fake"), minimum: CGSize = .zero
    ) {
        current = frame
        self.app = app
        self.minimum = minimum
    }

    func frame() -> CGRect? { current }

    func place(_ placement: SnapPlacement) -> Bool {
        placements.append(placement)
        guard accepts else { return false }
        let size = CGSize(width: max(placement.frame.width, minimum.width), height: max(placement.frame.height, minimum.height))
        current = goesSilentOnceMoved ? nil : CGRect(origin: placement.origin(for: size), size: size)
        return true
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
    private var hasMoved = false
    private(set) var calls: [String] = []

    init(frame: CGRect = CGRect(x: 100, y: 100, width: 800, height: 600)) {
        origin = frame.origin
        windowSize = frame.size
    }

    var frame: CGRect { CGRect(origin: origin, size: windowSize) }

    func position() -> CGPoint? { origin }

    func size() -> CGSize? { canReadSize ? windowSize : nil }

    func setPosition(_ position: CGPoint) -> Bool {
        calls.append("position")
        guard isMovable else { return false }
        origin = position
        hasMoved = true
        return true
    }

    func setSize(_ requested: CGSize) -> Bool {
        calls.append("size")
        guard isResizable else { return false }
        var granted = CGSize(width: max(requested.width, minimum.width), height: max(requested.height, minimum.height))
        if let maximum { granted = CGSize(width: min(granted.width, maximum.width), height: min(granted.height, maximum.height)) }
        if !hasMoved, let limit = sizeLimitUntilMoved {
            granted = CGSize(width: max(min(granted.width, limit.width), minimum.width), height: max(min(granted.height, limit.height), minimum.height))
        }
        windowSize = granted
        return true
    }
}
