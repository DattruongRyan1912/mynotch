import AppKit

enum ColorPickerEvent {
    case moved(CGPoint, shift: Bool)
    case down(CGPoint, shift: Bool, cmd: Bool)
    case key(ColorPickerInteraction.Key)
}

/// Renders the frozen display screen and the interactive pixel magnifier glass & HUD.
final class ColorPickerView: NSView {
    var onEvent: ((ColorPickerEvent) -> Void)?

    private let display: DisplayInfo
    private var image: CGImage?

    private let lensView = MagnifierLensView()
    private let hudView = ColorPickerHUDView()
    private let hintLabel = SelectionLabel()

    init(display: DisplayInfo, image: CGImage) {
        self.display = display
        self.image = image
        super.init(frame: CGRect(origin: .zero, size: display.frame.size))

        wantsLayer = true
        layer?.contentsGravity = .resize

        lensView.isHidden = true
        hudView.isHidden = true
        hintLabel.layer.contentsScale = display.scale

        addSubview(lensView)
        addSubview(hudView)
        layer?.addSublayer(hintLabel.layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.contents = image }

    func releaseImage() {
        image = nil
        layer?.contents = nil
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func apply(
        interaction: ColorPickerInteraction,
        isActiveDisplay: Bool
    ) {
        if !isActiveDisplay {
            lensView.isHidden = true
            hudView.isHidden = true
            hintLabel.layer.isHidden = true
            return
        }

        lensView.isHidden = false
        hudView.isHidden = false
        hintLabel.layer.isHidden = false

        let local = localPoint(interaction.virtualPointer)

        // 1. Position Lens View (132x132pt)
        let lensSize: CGFloat = 132.0
        lensView.frame = CGRect(
            x: local.x - lensSize / 2.0,
            y: local.y - lensSize / 2.0,
            width: lensSize,
            height: lensSize
        )
        lensView.update(
            grid: interaction.currentGrid,
            currentColor: interaction.currentColor
        )

        // 2. Position HUD View
        let hudSize = hudView.measureSize(pickedCount: interaction.pickedColors.count)
        var hudX = local.x - hudSize.width / 2.0
        // Clamp horizontally inside screen
        hudX = min(max(hudX, 12.0), bounds.width - hudSize.width - 12.0)

        // Place HUD below lens, or flip above if near bottom edge
        let spaceBelow = local.y - (lensSize / 2.0)
        let hudY: CGFloat
        if spaceBelow < hudSize.height + 24.0 {
            // Flip above
            hudY = local.y + (lensSize / 2.0) + 12.0
        } else {
            // Below
            hudY = local.y - (lensSize / 2.0) - hudSize.height - 12.0
        }

        hudView.frame = CGRect(x: hudX, y: hudY, width: hudSize.width, height: hudSize.height)
        hudView.update(
            sample: interaction.currentColor,
            format: interaction.format,
            pixelX: interaction.pixelX,
            pixelY: interaction.pixelY,
            pickedColors: interaction.pickedColors
        )

        // 3. Position Hint Label at bottom center
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hintLabel.setText(interaction.hint, scale: display.scale)
        let hintFrame = CGRect(
            x: (bounds.width - hintLabel.layer.bounds.width) / 2.0,
            y: 24.0,
            width: hintLabel.layer.bounds.width,
            height: hintLabel.layer.bounds.height
        )
        hintLabel.layer.frame = hintFrame
        CATransaction.commit()
    }

    private func localPoint(_ globalPoint: CGPoint) -> CGPoint {
        CGPoint(x: globalPoint.x - display.frame.minX, y: globalPoint.y - display.frame.minY)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        onEvent?(.moved(NSEvent.mouseLocation, shift: shift))
    }

    override func mouseDragged(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        onEvent?(.moved(NSEvent.mouseLocation, shift: shift))
    }

    override func mouseDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        let cmd = event.modifierFlags.contains(.command)
        onEvent?(.down(NSEvent.mouseLocation, shift: shift, cmd: cmd))
    }

    override func flagsChanged(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        onEvent?(.moved(NSEvent.mouseLocation, shift: shift))
    }

    override func keyDown(with event: NSEvent) {
        guard let key = ColorPickerInteraction.Key.key(forKeyCode: event.keyCode) else { return }
        // Allow repeat for arrow/WASD nudges, suppress repeat for terminal keys
        if event.isARepeat {
            switch key {
            case .up, .down, .left, .right:
                break
            case .escape, .tab, .space, .returnKey:
                return
            }
        }
        onEvent?(.key(key))
    }
}

// MARK: - Magnifier Lens View

private final class MagnifierLensView: NSView {
    private var grid: [[ColorSample]] = []
    private var currentColor = ColorSample(red: 0, green: 0, blue: 0)

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(grid: [[ColorSample]], currentColor: ColorSample) {
        self.grid = grid
        self.currentColor = currentColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let size = bounds.size
        guard size.width > 0 && size.height > 0 else { return }

        ctx.saveGState()

        // 1. Clip circle for the lens interior
        let circleRect = bounds.insetBy(dx: 1, dy: 1)
        ctx.addEllipse(in: circleRect)
        ctx.clip()

        // 2. Draw 11x11 grid cells
        let cellCount = 11
        let cellWidth = size.width / CGFloat(cellCount)
        let cellHeight = size.height / CGFloat(cellCount)

        for row in 0..<cellCount {
            for col in 0..<cellCount {
                let cellRect = CGRect(
                    x: CGFloat(col) * cellWidth,
                    y: size.height - CGFloat(row + 1) * cellHeight,
                    width: cellWidth,
                    height: cellHeight
                )
                let sample: ColorSample
                if row < grid.count && col < grid[row].count {
                    sample = grid[row][col]
                } else {
                    sample = ColorSample(red: 0, green: 0, blue: 0)
                }

                ctx.setFillColor(sample.cgColor)
                ctx.fill(cellRect)
            }
        }

        // 3. Draw grid lines
        ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 0.12))
        ctx.setLineWidth(1.0)
        for i in 1..<cellCount {
            let x = CGFloat(i) * cellWidth
            ctx.move(to: CGPoint(x: x, y: 0))
            ctx.addLine(to: CGPoint(x: x, y: size.height))
            let y = CGFloat(i) * cellHeight
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: size.width, y: y))
        }
        ctx.strokePath()

        // 4. Draw Center Pixel Crosshair (cell 5, 5)
        let centerCol = 5
        let centerRow = 5
        let centerRect = CGRect(
            x: CGFloat(centerCol) * cellWidth,
            y: size.height - CGFloat(centerRow + 1) * cellHeight,
            width: cellWidth,
            height: cellHeight
        )

        let crosshairDark = currentColor.prefersDarkCrosshair
        ctx.setLineWidth(2.0)
        ctx.setStrokeColor(crosshairDark ? CGColor(gray: 0.0, alpha: 0.9) : CGColor(gray: 1.0, alpha: 0.9))
        ctx.stroke(centerRect.insetBy(dx: 1.0, dy: 1.0))

        ctx.setLineWidth(1.0)
        ctx.setStrokeColor(crosshairDark ? CGColor(gray: 1.0, alpha: 0.9) : CGColor(gray: 0.0, alpha: 0.9))
        ctx.stroke(centerRect.insetBy(dx: 2.0, dy: 2.0))

        ctx.restoreGState()

        // 5. Draw Outer Rings (double border for high contrast)
        ctx.saveGState()
        // Outer dark ring
        ctx.setLineWidth(2.5)
        ctx.setStrokeColor(CGColor(gray: 0.08, alpha: 0.85))
        ctx.strokeEllipse(in: bounds.insetBy(dx: 1.25, dy: 1.25))

        // Inner white hairline ring
        ctx.setLineWidth(1.5)
        ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 0.95))
        ctx.strokeEllipse(in: bounds.insetBy(dx: 2.75, dy: 2.75))
        ctx.restoreGState()
    }
}

// MARK: - Color Picker HUD View

private final class ColorPickerHUDView: NSView {
    private var sample = ColorSample(red: 0, green: 0, blue: 0)
    private var format = ColorFormat.hex
    private var pixelX = 0
    private var pixelY = 0
    private var pickedColors: [ColorSample] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = CGColor(gray: 0.04, alpha: 0.92)
        layer?.borderColor = CGColor(gray: 0.2, alpha: 0.8)
        layer?.borderWidth = 1.0
        layer?.cornerRadius = 7.0
        layer?.shadowColor = CGColor(gray: 0.0, alpha: 0.5)
        layer?.shadowOpacity = 0.6
        layer?.shadowRadius = 8.0
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func measureSize(pickedCount: Int) -> CGSize {
        let height: CGFloat = pickedCount > 0 ? 66.0 : 46.0
        return CGSize(width: 172.0, height: height)
    }

    func update(
        sample: ColorSample,
        format: ColorFormat,
        pixelX: Int,
        pixelY: Int,
        pickedColors: [ColorSample]
    ) {
        self.sample = sample
        self.format = format
        self.pixelX = pixelX
        self.pixelY = pixelY
        self.pickedColors = pickedColors
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let size = bounds.size
        guard size.width > 0 && size.height > 0 else { return }

        // Swatch square
        let swatchRect = CGRect(x: 10.0, y: size.height - 28.0, width: 18.0, height: 18.0)
        let swatchPath = CGPath(roundedRect: swatchRect, cornerWidth: 4.0, cornerHeight: 4.0, transform: nil)
        ctx.addPath(swatchPath)
        ctx.setFillColor(sample.cgColor)
        ctx.fillPath()

        ctx.addPath(swatchPath)
        ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 0.25))
        ctx.setLineWidth(1.0)
        ctx.strokePath()

        // Text strings using CTLine for crisp CoreGraphics typography
        let valString = sample.formatted(as: format)
        let valFont = NSFont.monospacedSystemFont(ofSize: 13.0, weight: .bold)
        let valAttr: [NSAttributedString.Key: Any] = [
            .font: valFont,
            .foregroundColor: NSColor.white
        ]
        let valAttrStr = NSAttributedString(string: valString, attributes: valAttr)
        let valLine = CTLineCreateWithAttributedString(valAttrStr)

        ctx.textPosition = CGPoint(x: 34.0, y: size.height - 25.0)
        CTLineDraw(valLine, ctx)

        // Subtitle (Format · X, Y)
        let subString = "\(format.shortTitle) · \(pixelX), \(pixelY)"
        let subFont = NSFont.monospacedDigitSystemFont(ofSize: 10.0, weight: .regular)
        let subAttr: [NSAttributedString.Key: Any] = [
            .font: subFont,
            .foregroundColor: NSColor(white: 0.65, alpha: 1.0)
        ]
        let subAttrStr = NSAttributedString(string: subString, attributes: subAttr)
        let subLine = CTLineCreateWithAttributedString(subAttrStr)

        ctx.textPosition = CGPoint(x: 34.0, y: size.height - 38.0)
        CTLineDraw(subLine, ctx)

        // Multi-picked swatches row (if any)
        if !pickedColors.isEmpty {
            let swatchSize: CGFloat = 14.0
            let gap: CGFloat = 6.0
            let startX: CGFloat = 10.0
            let rowY: CGFloat = 8.0

            for (idx, pColor) in pickedColors.enumerated() {
                let rect = CGRect(x: startX + CGFloat(idx) * (swatchSize + gap), y: rowY, width: swatchSize, height: swatchSize)
                let path = CGPath(roundedRect: rect, cornerWidth: 3.0, cornerHeight: 3.0, transform: nil)
                ctx.addPath(path)
                ctx.setFillColor(pColor.cgColor)
                ctx.fillPath()

                ctx.addPath(path)
                ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 0.5))
                ctx.setLineWidth(1.0)
                ctx.strokePath()
            }
        }
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
