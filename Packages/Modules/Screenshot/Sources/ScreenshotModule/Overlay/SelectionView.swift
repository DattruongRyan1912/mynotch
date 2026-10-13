import AppKit
import QuartzCore

/// What a panel's view reports to the controller; positions are read from `NSEvent.mouseLocation`.
enum SelectionEvent {
    case moved, down, dragged, up
    case key(OverlayInteraction.Key)
}

/// The frozen screen of one display with everything but the selection dimmed. Drawn with layers, so the image
/// stays one texture and a drag only moves a mask: redrawing a 6K image on every mouse event would lag.
final class SelectionView: NSView {
    var onEvent: ((SelectionEvent) -> Void)?

    private let display: DisplayInfo
    private var image: CGImage?
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let sizeLabel = SelectionLabel()
    private let hintLabel = SelectionLabel()

    init(display: DisplayInfo, image: CGImage) {
        self.display = display
        self.image = image
        super.init(frame: CGRect(origin: .zero, size: display.frame.size))
        wantsLayer = true
        layer?.contentsGravity = .resize
        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.45).cgColor
        dimLayer.fillRule = .evenOdd
        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.white.cgColor
        borderLayer.lineWidth = 1
        [dimLayer, borderLayer, sizeLabel.layer, hintLabel.layer].forEach { layer?.addSublayer($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The layer shows the frozen image as one texture. `updateLayer` sets it, so AppKit never replaces it with a drawing.
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.contents = image }

    /// Lets go of the frozen image at once; the view may outlive its panel for a moment.
    func releaseImage() {
        image = nil
        layer?.contents = nil
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Dims everything outside `highlight` and labels it; only the display holding the selection shows a label.
    func apply(_ highlight: OverlayInteraction.Highlight, hint: String) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        var hole: CGRect?
        var size: CGSize?
        var isSelecting = false
        switch highlight {
        case .none:
            break
        case .region(let displayID, let rect, let pixelSize):
            isSelecting = true
            if displayID == display.id {
                hole = localRect(rect)
                size = pixelSize
            }
        case .window(let rect):
            let visible = rect.intersection(display.frame)
            if !visible.isNull, !visible.isEmpty { hole = localRect(visible) }
        }
        let mask = CGMutablePath()
        mask.addRect(bounds)
        if let hole { mask.addRect(hole) }
        dimLayer.path = mask
        borderLayer.path = hole.map { CGPath(rect: $0, transform: nil) }
        placeSizeLabel(size, around: hole)
        placeHint(hint, hidden: isSelecting)
    }

    // MARK: Layout

    private func localRect(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
    }

    /// Above the selection's top edge, or inside it when there is no room above.
    private func placeSizeLabel(_ size: CGSize?, around hole: CGRect?) {
        guard let size, let hole else {
            sizeLabel.layer.isHidden = true
            return
        }
        sizeLabel.setText("\(Int(size.width)) × \(Int(size.height))", scale: backingScale)
        let labelSize = sizeLabel.layer.bounds.size
        let aboveY = hole.maxY + 6
        let y = aboveY + labelSize.height <= bounds.maxY ? aboveY : hole.maxY - labelSize.height - 6
        let x = min(max(hole.minX, 4), max(bounds.maxX - labelSize.width - 4, 4))
        sizeLabel.layer.frame = CGRect(origin: CGPoint(x: x, y: y), size: labelSize)
        sizeLabel.layer.isHidden = false
    }

    private func placeHint(_ text: String, hidden: Bool) {
        hintLabel.layer.isHidden = hidden
        guard !hidden else { return }
        hintLabel.setText(text, scale: backingScale)
        let size = hintLabel.layer.bounds.size
        // Above a typical Dock, so the hint does not hide its icons.
        hintLabel.layer.frame = CGRect(x: (bounds.width - size.width) / 2, y: max(bounds.height * 0.1, 96), width: size.width, height: size.height)
    }

    private var backingScale: CGFloat { window?.backingScaleFactor ?? display.scale }

    // MARK: Events

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.activeAlways, .mouseMoved, .cursorUpdate, .inVisibleRect], owner: self, userInfo: nil
        ))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    /// The app is never active, so cursor rects alone are not enough to keep the crosshair.
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        onEvent?(.moved)
    }

    override func mouseDown(with event: NSEvent) { onEvent?(.down) }
    override func mouseDragged(with event: NSEvent) { onEvent?(.dragged) }
    override func mouseUp(with event: NSEvent) { onEvent?(.up) }

    override func keyDown(with event: NSEvent) {
        // A held Space would otherwise flip the mode back and forth.
        guard !event.isARepeat, let key = OverlayInteraction.key(forKeyCode: event.keyCode) else { return }
        onEvent?(.key(key))
    }
}

/// A small dark pill with white text.
private final class SelectionLabel {
    private static let padding = CGSize(width: 8, height: 3)

    let layer = CALayer()
    private let textLayer = CATextLayer()

    init() {
        layer.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        layer.cornerRadius = 5
        layer.addSublayer(textLayer)
        layer.isHidden = true
    }

    /// Sizes the pill to the text; the caller then positions it with `layer.frame`.
    func setText(_ text: String, scale: CGFloat) {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
        let textSize = attributed.size()
        let size = CGSize(width: ceil(textSize.width), height: ceil(textSize.height))
        textLayer.contentsScale = scale
        textLayer.string = attributed
        textLayer.frame = CGRect(origin: CGPoint(x: Self.padding.width, y: Self.padding.height), size: size)
        layer.bounds = CGRect(x: 0, y: 0, width: size.width + 2 * Self.padding.width, height: size.height + 2 * Self.padding.height)
    }
}
