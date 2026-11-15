import AppKit
import CoreGraphics

/// View rendering the pinned screenshot image, close button overlay, zoom/opacity badge, and gestures.
@MainActor
final class PinnedWindowView: NSView {
    let item: PinnedItem
    var state: PinnedWindowState
    var actions: PinnedWindowActions
    var onClose: (@MainActor () -> Void)?

    private var isHovered = false
    private let closeButtonSize: CGFloat = 22.0
    private let closeButtonMargin: CGFloat = 8.0

    init(
        item: PinnedItem,
        state: PinnedWindowState,
        actions: PinnedWindowActions,
        onClose: (@MainActor () -> Void)? = nil
    ) {
        self.item = item
        self.state = state
        self.actions = actions
        self.onClose = onClose
        super.init(frame: NSRect(origin: .zero, size: state.currentSize))
        wantsLayer = true
        layer?.cornerRadius = 8.0
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    private var closeButtonRect: CGRect {
        CGRect(
            x: bounds.width - closeButtonSize - closeButtonMargin,
            y: bounds.height - closeButtonSize - closeButtonMargin,
            width: closeButtonSize,
            height: closeButtonSize
        )
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let bounds = self.bounds
        guard bounds.width > 0 && bounds.height > 0 else { return }

        ctx.saveGState()

        // 1. Clip rounded rect
        let cornerRadius: CGFloat = 8.0
        let clipPath = CGPath(
            roundedRect: bounds,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        ctx.addPath(clipPath)
        ctx.clip()

        // 2. Draw screenshot image
        ctx.draw(item.image, in: bounds)

        // 3. Hairline border (Anti-AI-Slop dark zinc aesthetic)
        ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 0.18))
        ctx.setLineWidth(1.0)
        ctx.addPath(clipPath)
        ctx.strokePath()

        // 4. Overlays when hovered
        if isHovered {
            drawCloseButton(in: ctx)
            drawStatusBadge(in: ctx)
        }

        ctx.restoreGState()
    }

    private func drawCloseButton(in ctx: CGContext) {
        let rect = closeButtonRect
        ctx.saveGState()

        // Dark circular background
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 0.82))
        ctx.fillEllipse(in: rect)

        // Hairline border
        ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 0.25))
        ctx.setLineWidth(1.0)
        ctx.strokeEllipse(in: rect)

        // Draw '✕'
        let inset: CGFloat = 6.0
        let crossRect = rect.insetBy(dx: inset, dy: inset)
        ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 0.9))
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)

        ctx.beginPath()
        ctx.move(to: CGPoint(x: crossRect.minX, y: crossRect.minY))
        ctx.addLine(to: CGPoint(x: crossRect.maxX, y: crossRect.maxY))
        ctx.move(to: CGPoint(x: crossRect.minX, y: crossRect.maxY))
        ctx.addLine(to: CGPoint(x: crossRect.maxX, y: crossRect.minY))
        ctx.strokePath()

        ctx.restoreGState()
    }

    private func drawStatusBadge(in ctx: CGContext) {
        guard state.zoom != 1.0 || state.opacity != 1.0 else { return }
        let zoomPercent = Int(round(state.zoom * 100))
        let opacityPercent = Int(round(state.opacity * 100))
        let text = "\(zoomPercent)% · \(opacityPercent)%"

        let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(white: 1.0, alpha: 0.88)
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrString.size()

        let badgeH: CGFloat = 20.0
        let badgeW = textSize.width + 12.0
        let badgeRect = CGRect(x: 8.0, y: 8.0, width: badgeW, height: badgeH)

        ctx.saveGState()
        let badgePath = CGPath(roundedRect: badgeRect, cornerWidth: 5.0, cornerHeight: 5.0, transform: nil)
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 0.82))
        ctx.addPath(badgePath)
        ctx.fillPath()

        ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 0.18))
        ctx.setLineWidth(1.0)
        ctx.addPath(badgePath)
        ctx.strokePath()

        let textPoint = CGPoint(
            x: badgeRect.minX + 6.0,
            y: badgeRect.minY + (badgeH - textSize.height) / 2.0
        )
        attrString.draw(at: textPoint)
        ctx.restoreGState()
    }

    // MARK: - Event Handling

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if isHovered && closeButtonRect.contains(location) {
            onClose?()
            return
        }
        if event.clickCount == 2 {
            onClose?()
            return
        }
        window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard let window else { return }
        let localAnchor = convert(event.locationInWindow, from: nil)
        let newFrame = state.applyScrollDelta(
            event.scrollingDeltaY,
            currentFrame: window.frame,
            anchorInWindow: localAnchor
        )
        window.setFrame(newFrame, display: true)
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        guard let window else { return }
        let localAnchor = convert(event.locationInWindow, from: nil)
        let newFrame = state.setZoom(
            state.zoom * (1.0 + event.magnification),
            currentFrame: window.frame,
            anchorInWindow: localAnchor
        )
        window.setFrame(newFrame, display: true)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 || (event.charactersIgnoringModifiers == "w" && event.modifierFlags.contains(.command)) {
            onClose?()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: "PinnedWindowMenu")

        let copyItem = NSMenuItem(title: "Chép ảnh", action: #selector(handleCopy), keyEquivalent: "c")
        copyItem.target = self
        menu.addItem(copyItem)

        let ocrItem = NSMenuItem(title: "OCR (chép chữ)", action: #selector(handleOCR), keyEquivalent: "")
        ocrItem.target = self
        menu.addItem(ocrItem)

        if actions.liftSubject != nil {
            let liftItem = NSMenuItem(title: "Tách chủ thể", action: #selector(handleLiftSubject), keyEquivalent: "")
            liftItem.target = self
            menu.addItem(liftItem)
        }

        if actions.edit != nil {
            let editItem = NSMenuItem(title: "Sửa ảnh…", action: #selector(handleEdit), keyEquivalent: "e")
            editItem.target = self
            menu.addItem(editItem)
        }

        if actions.saveAs != nil {
            let saveItem = NSMenuItem(title: "Lưu thành…", action: #selector(handleSaveAs), keyEquivalent: "s")
            saveItem.target = self
            menu.addItem(saveItem)
        }

        menu.addItem(NSMenuItem.separator())

        // Submenu: Zoom
        let zoomMenu = NSMenu(title: "Thu phóng")
        for preset in PinnedWindowState.zoomPresets {
            let percent = Int(preset * 100)
            let item = NSMenuItem(title: "\(percent)%", action: #selector(handleZoomPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            if abs(state.zoom - preset) < 0.01 {
                item.state = .on
            }
            zoomMenu.addItem(item)
        }
        let zoomSubmenuItem = NSMenuItem(title: "Thu phóng", action: nil, keyEquivalent: "")
        zoomSubmenuItem.submenu = zoomMenu
        menu.addItem(zoomSubmenuItem)

        // Submenu: Opacity
        let opacityMenu = NSMenu(title: "Độ mờ")
        for preset in PinnedWindowState.opacityPresets {
            let percent = Int(preset * 100)
            let item = NSMenuItem(title: "\(percent)%", action: #selector(handleOpacityPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            if abs(state.opacity - preset) < 0.01 {
                item.state = .on
            }
            opacityMenu.addItem(item)
        }
        let opacitySubmenuItem = NSMenuItem(title: "Độ mờ", action: nil, keyEquivalent: "")
        opacitySubmenuItem.submenu = opacityMenu
        menu.addItem(opacitySubmenuItem)

        menu.addItem(NSMenuItem.separator())

        let closeItem = NSMenuItem(title: "Đóng", action: #selector(handleClose), keyEquivalent: "w")
        closeItem.target = self
        menu.addItem(closeItem)

        return menu
    }

    @objc private func handleCopy() {
        actions.copy()
    }

    @objc private func handleOCR() {
        actions.ocr()
    }

    @objc private func handleLiftSubject() {
        actions.liftSubject?()
    }

    @objc private func handleEdit() {
        onClose?()
        actions.edit?()
    }

    @objc private func handleSaveAs() {
        actions.saveAs?()
    }

    @objc private func handleZoomPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? CGFloat, let window else { return }
        let newFrame = state.setZoom(preset, currentFrame: window.frame)
        window.setFrame(newFrame, display: true)
        needsDisplay = true
    }

    @objc private func handleOpacityPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? CGFloat, let window else { return }
        state.setOpacity(preset)
        window.alphaValue = state.opacity
        needsDisplay = true
    }

    @objc private func handleClose() {
        onClose?()
    }
}
