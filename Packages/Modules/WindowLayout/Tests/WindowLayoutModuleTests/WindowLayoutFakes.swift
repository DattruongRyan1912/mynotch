import CoreGraphics
@testable import WindowLayoutModule

/// A window that records what it was asked, so no real window is ever moved. Frames are in Accessibility coordinates.
final class FakeWindow: SnapWindow {
    var current: CGRect?
    private(set) var setFrames: [CGRect] = []
    /// What `setFrame` answers: an app that refuses to be moved.
    var accepts = true

    init(frame: CGRect? = CGRect(x: 100, y: 100, width: 800, height: 600)) {
        current = frame
    }

    func frame() -> CGRect? { current }

    func setFrame(_ frame: CGRect) -> Bool {
        setFrames.append(frame)
        guard accepts else { return false }
        current = frame
        return true
    }

    func isSame(as other: any SnapWindow) -> Bool { other === self }

    /// The user dragging the window: it moves, its size stays.
    func drag(to origin: CGPoint) {
        guard let frame = current else { return }
        current = CGRect(origin: origin, size: frame.size)
    }
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
