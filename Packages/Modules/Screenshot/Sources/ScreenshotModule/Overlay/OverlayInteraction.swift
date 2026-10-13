import CoreGraphics

/// The decisions of the selection overlay, free of AppKit: which key does what, what a drag selects, which window
/// the pointer is over. The panels only forward events here and draw `highlight`. All points are AppKit global
/// points (what `NSEvent.mouseLocation` reports), the same space as `DisplayInfo.frame`.
nonisolated struct OverlayInteraction {
    /// A selection smaller than this on either side is a stray click or twitch, not a capture.
    static let minimumPixelSize: CGFloat = 4

    enum Key: Equatable {
        case escape, space, returnKey
    }

    enum Outcome: Equatable {
        /// Nothing to finish; the state may still have changed, so redraw.
        case none
        case cancel
        case finish(CaptureResult)
    }

    /// What the panels draw: the part of the screen that stays undimmed.
    enum Highlight: Equatable {
        case none
        /// A selection on one display, snapped to its pixels, with the size it will have.
        case region(displayID: CGDirectDisplayID, rect: CGRect, pixelSize: CGSize)
        case window(rect: CGRect)
    }

    private struct Drag {
        var display: DisplayInfo
        var start: CGPoint
        var pixelRect: CGRect = .zero
    }

    private let mode: SelectionMode
    private let displays: [DisplayInfo]
    private let windows: [CapturableWindow]
    private let excludingPID: pid_t
    private let primaryHeight: CGFloat
    private var drag: Drag?
    private var hoveredWindow: CapturableWindow?
    /// The window a press landed on in window mode; the click counts once the button is released over it too.
    private var pressedWindow: CGWindowID?

    private(set) var isWindowMode = false
    private(set) var highlight: Highlight = .none

    /// `windows` are in CG global points, front to back; windows of `excludingPID` (MyNotch) are never offered.
    init(mode: SelectionMode, displays: [DisplayInfo], windows: [CapturableWindow], excludingPID: pid_t) {
        self.mode = mode
        self.displays = displays
        self.windows = windows
        self.excludingPID = excludingPID
        primaryHeight = GeometryMapper.primaryHeight(of: displays) ?? displays.map(\.frame.maxY).max() ?? 0
    }

    /// The keys that matter to the overlay; everything else is ignored.
    static func key(forKeyCode keyCode: UInt16) -> Key? {
        switch keyCode {
        case 53: .escape
        case 49: .space
        case 36, 76: .returnKey
        default: nil
        }
    }

    /// One line telling which keys apply now.
    var hint: String {
        switch mode {
        case .regionOrWindow where isWindowMode:
            "Bấm vào cửa sổ để chụp  ·  Space: chọn vùng  ·  Return: cả màn hình  ·  Esc: huỷ"
        case .regionOrWindow:
            "Kéo để chọn vùng  ·  Space: chọn cửa sổ  ·  Return: cả màn hình  ·  Esc: huỷ"
        case .region:
            "Kéo để chọn vùng  ·  Return: cả màn hình  ·  Esc: huỷ"
        case .ocrRegion:
            "Kéo để chọn vùng chứa chữ cần chép  ·  Return: cả màn hình  ·  Esc: huỷ"
        }
    }

    mutating func keyDown(_ key: Key, pointer: CGPoint) -> Outcome {
        switch key {
        case .escape:
            return .cancel
        case .returnKey:
            guard let display = GeometryMapper.display(containing: pointer, in: displays) ?? displays.first else { return .cancel }
            return .finish(.fullScreen(displayID: display.id))
        case .space:
            guard mode == .regionOrWindow, drag == nil else { return .none }
            isWindowMode.toggle()
            pressedWindow = nil
            updateHover(at: pointer)
            return .none
        }
    }

    mutating func pointerMoved(to point: CGPoint) {
        updateHover(at: point)
    }

    mutating func mouseDown(at point: CGPoint) -> Outcome {
        if isWindowMode {
            updateHover(at: point)
            pressedWindow = hoveredWindow?.id
            return .none
        }
        guard let display = GeometryMapper.display(containing: point, in: displays) else { return .none }
        drag = Drag(display: display, start: point)
        highlight = .none
        return .none
    }

    mutating func mouseDragged(to point: CGPoint) {
        update(drag: point)
    }

    /// Ends the drag; a selection of at least `minimumPixelSize` on both sides is the result. In window mode it
    /// completes a click, so the app below never sees half of one.
    mutating func mouseUp(at point: CGPoint) -> Outcome {
        if isWindowMode {
            updateHover(at: point)
            defer { pressedWindow = nil }
            guard let pressedWindow, hoveredWindow?.id == pressedWindow else { return .none }
            return .finish(.window(pressedWindow))
        }
        guard drag != nil else { return .none }
        update(drag: point)
        guard let drag else { return .none }
        self.drag = nil
        let pixels = drag.pixelRect
        guard pixels.width >= Self.minimumPixelSize, pixels.height >= Self.minimumPixelSize else {
            highlight = .none
            return .none
        }
        return .finish(.region(displayID: drag.display.id, pixelRect: pixels))
    }

    /// The selection is clamped to the display where the drag began, then snapped to its pixels; the highlight
    /// and the crop rect both come from that one rect.
    private mutating func update(drag point: CGPoint) {
        guard var drag else { return }
        let display = drag.display
        let dragged = GeometryMapper.normalizedSelection(from: drag.start, to: point)
        let selection = GeometryMapper.snapped(GeometryMapper.clamp(dragged, to: display), to: display)
        drag.pixelRect = GeometryMapper.pixelRect(for: selection, on: display)
        self.drag = drag
        highlight = drag.pixelRect.isEmpty
            ? .none
            : .region(displayID: display.id, rect: selection, pixelSize: drag.pixelRect.size)
    }

    /// Window mode highlights the window under the pointer; leaving it removes that highlight.
    private mutating func updateHover(at point: CGPoint) {
        guard isWindowMode else {
            hoveredWindow = nil
            if drag == nil { highlight = .none }
            return
        }
        let cgPoint = CGPoint(x: point.x, y: primaryHeight - point.y)
        hoveredWindow = WindowHitTester.window(at: cgPoint, in: windows, excludingPID: excludingPID)
        highlight = hoveredWindow.map { .window(rect: GeometryMapper.appKitRect(fromCG: $0.bounds, primaryHeight: primaryHeight)) } ?? .none
    }
}
