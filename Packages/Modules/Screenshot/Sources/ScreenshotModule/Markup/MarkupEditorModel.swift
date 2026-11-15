import CoreGraphics
import MyNotchCore
import Observation

/// Text being typed in the editor before it becomes an annotation.
nonisolated struct TextDraft: Equatable, Sendable {
    /// Image pixels: the top-left of the first line.
    var origin: CGPoint
    var string = ""
    /// Image pixels per view point when the text was placed, which turns the chosen size into pixels.
    var pixelsPerPoint: CGFloat
}

/// What a drag of the crop tool does, decided where it began and kept until it ends.
private nonisolated struct CropGesture {
    let start: CGPoint
    /// The frame as the drag found it, which every move of the pointer is applied to; nil when there was none.
    let frame: CropFrame?
    let grab: CropGrab
}

/// The markup editor's state: tool choices, the shape being drawn, inline text, undo history and the flattened
/// preview. Gesture positions arrive already converted to annotation pixels (origin at the capture's top-left, so
/// they may be negative or past its far edges), so the view only handles layout.
@Observable final class MarkupEditorModel {
    let image: CGImage
    /// The capture's pixels per point, for the ruler's label.
    let pointScale: CGFloat
    private(set) var tool: MarkupTool = .arrow
    /// The tool the crop tool returns to once the frame is applied or cancelled.
    @ObservationIgnored private var toolBeforeCrop: MarkupTool = .arrow
    var color: RGBAColor = .red
    var thickness: StrokeThickness = .medium
    var magnification: CGFloat = 2
    /// The shape under the pointer during a drag, drawn live over the preview.
    private(set) var draft: Annotation?
    var text: TextDraft?
    /// The canvas with every committed annotation burned in and cut to the crop, as it will be saved.
    private(set) var preview: CGImage
    /// The same before the crop: the whole canvas, which the crop tool shows so the frame can reach every pixel.
    private(set) var canvasPreview: CGImage
    /// How far the canvas reaches past the capture, from the annotations that stick out.
    private(set) var canvas: CanvasInsets
    /// The part of annotation space `preview` shows: the crop, or else the whole canvas.
    private(set) var outputBounds: CGRect
    /// The crop frame being dragged, in annotation pixels, not applied yet.
    private(set) var cropFrame: CGRect?
    private(set) var cropAspect: CropAspect = .free
    var isShowingStudioFrame = false
    var studioFrame: StudioFrameConfig { document.studioFrame ?? StudioFrameConfig() }
    static let zoomRange: ClosedRange<CGFloat> = 0.25...32.0
    static let zoomStep: CGFloat = 1.25
    private(set) var zoomScale: CGFloat = 1.0
    private(set) var panOffset: CGSize = .zero
    @ObservationIgnored var lastViewportSize: CGSize = .zero
    private var history: UndoStack
    @ObservationIgnored private var dragPoints: [CGPoint] = []
    @ObservationIgnored private var cropGesture: CropGesture?
    @ObservationIgnored private let render: (CGImage, MarkupDocument) -> CGImage?

    /// `document` reopens earlier markup; it must belong to `image`. `pointScale` is the capture's pixels per point,
    /// and `canvasFill` is what padding is filled with; it replaces the document's, which is not saved. `render` makes
    /// the preview and is only replaced in tests, to see what happens when no bitmap can be made.
    init(
        image: CGImage, document: MarkupDocument? = nil, pointScale: CGFloat = 1, canvasFill: CanvasFill = .standard,
        render: @escaping (CGImage, MarkupDocument) -> CGImage? = MarkupRenderer.flatten
    ) {
        self.image = image
        self.pointScale = pointScale
        self.render = render
        var document = document ?? MarkupDocument(imageSize: CGSize(width: image.width, height: image.height))
        document.canvasFill = canvasFill
        history = UndoStack(document)
        // A document that cannot be drawn shows the plain capture, which is also all the canvas then is.
        let rendered = Self.rendered(image, document, using: render)
        canvas = rendered == nil ? .zero : document.canvas
        canvasPreview = rendered?.canvas ?? image
        preview = rendered?.saved ?? image
        outputBounds = rendered == nil ? CGRect(origin: .zero, size: document.imageSize) : Self.effectiveOutputBounds(for: document)
    }

    var document: MarkupDocument { history.document }
    var isCropping: Bool { tool == .crop }
    /// The part of annotation space the editor shows: the whole canvas while the crop tool is up, else the saved picture.
    var displayedBounds: CGRect { isCropping ? canvas.bounds(of: document.imageSize) : outputBounds }
    /// What the editor draws: `canvasPreview` while the crop tool is up, else `preview`.
    var displayedPreview: CGImage { isCropping ? canvasPreview : preview }
    var canvasSize: CGSize { displayedBounds.size }
    /// The annotation-space point at the top-left corner of what the editor shows.
    var canvasOrigin: CGPoint { displayedBounds.origin }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    /// The size of the text being typed, in image pixels.
    var textFontSize: CGFloat { thickness.fontSize * (text?.pixelsPerPoint ?? 1) }

    func select(_ tool: MarkupTool) {
        commitText()
        guard tool != self.tool else { return }
        if self.tool == .crop {
            // A frame that was not applied goes with the tool.
            cropFrame = nil
            cropGesture = nil
        }
        if tool == .crop {
            toolBeforeCrop = self.tool
            // The tool starts from the crop that is applied, so it can be widened again, and always starts free.
            cropFrame = document.cropWithinCanvas(canvas)
            cropAspect = .free
        }
        self.tool = tool
    }

    /// `start` and `end` are annotation pixels; `pixelsPerPoint` converts the view-sized thickness into pixels. A
    /// drawing tool may be dragged past the capture's edge, which grows the canvas when the shape is committed.
    func dragChanged(from start: CGPoint, to end: CGPoint, pixelsPerPoint: CGFloat, modifiers: MarkupModifiers = []) {
        guard tool != .crop else {
            dragCropFrame(from: start, to: end, pixelsPerPoint: pixelsPerPoint)
            return
        }
        guard tool != .text, !removesStep(modifiers) else { return }
        track(from: limited(start), to: limited(end), minimumStep: pixelsPerPoint)
        draft = tool.annotation(through: dragPoints, options: options(pixelsPerPoint, modifiers))
    }

    /// Commits the drawn shape, or for the text tool starts typing where the drag began. ⌥-clicking a step badge
    /// removes it instead.
    func dragEnded(from start: CGPoint, to end: CGPoint, pixelsPerPoint: CGFloat, modifiers: MarkupModifiers = []) {
        defer {
            dragPoints = []
            draft = nil
        }
        guard tool != .crop else {
            dragCropFrame(from: start, to: end, pixelsPerPoint: pixelsPerPoint)
            cropGesture = nil
            return
        }
        let start = limited(start), end = limited(end)
        if removesStep(modifiers) {
            removeStep(at: end)
            return
        }
        guard tool != .text else {
            commitText()
            text = TextDraft(origin: start, pixelsPerPoint: pixelsPerPoint)
            return
        }
        track(from: start, to: end, minimumStep: 0)
        guard let annotation = tool.annotation(through: dragPoints, options: options(pixelsPerPoint, modifiers)) else { return }
        edit { $0.apply { $0.annotations.append(annotation) } }
    }

    /// Adds the typed text, if any, as an annotation in the current colour and size.
    func commitText() {
        guard let text else { return }
        let fontSize = textFontSize
        self.text = nil
        guard !text.string.allSatisfy(\.isWhitespace) else { return }
        let annotation = Annotation.text(text.string, at: text.origin, fontSize: fontSize, color: color)
        edit { $0.apply { $0.annotations.append(annotation) } }
    }

    func setStudioFrame(_ config: StudioFrameConfig) {
        commitText()
        edit {
            $0.apply {
                $0.studioFrame = config
            }
        }
    }

    func toggleStudioFrame() {
        isShowingStudioFrame.toggle()
        if isShowingStudioFrame && (document.studioFrame == nil || document.studioFrame?.isActive == false) {
            setStudioFrame(.defaultActive)
        }
    }

    func cancelText() {
        text = nil
    }

    func undo() {
        edit { $0.undo() }
    }

    func redo() {
        edit { $0.redo() }
    }

    // MARK: Crop

    /// How far from a frame's corner or edge, in view points, the pointer takes hold of its handle.
    static let cropHandleReach: CGFloat = 10

    /// Chooses the frame's ratio. A fixed one reshapes the frame there is to the biggest of that ratio inside it, or makes
    /// the biggest one that fits the canvas when there is none.
    func setCropAspect(_ aspect: CropAspect) {
        guard isCropping else { return }
        cropAspect = aspect
        guard let ratio = aspect.ratio(of: document.imageSize) else { return }
        if let cropFrame {
            self.cropFrame = CropFrame(rect: cropFrame, bounds: canvas.bounds(of: document.imageSize), ratio: ratio).fitting(ratio: ratio).rect
        } else {
            cropFrame = CropFrame.largest(ratio: ratio, in: canvas.bounds(of: document.imageSize)).rect
        }
    }

    /// Cuts the canvas to the frame as one undoable step and goes back to the tool that was in use. Annotations the
    /// crop leaves nothing of are removed with it, and the step badges after them renumbered; the others keep their
    /// coordinates, so undoing brings everything back. A frame that is the whole canvas is no crop at all.
    func applyCrop() {
        guard isCropping else { return }
        let frame = cropFrame
        leaveCropTool()
        guard let frame else { return }
        let canvasBounds = canvas.bounds(of: document.imageSize)
        let rect = CropFrame(rect: frame, bounds: canvasBounds, ratio: nil).pixelRect
        guard rect.width >= 1, rect.height >= 1 else { return }
        let crop: CGRect? = rect == canvasBounds ? nil : rect
        edit {
            $0.apply { document in
                document.crop = crop
                guard let crop else { return }
                let kept = document.annotations.filter { $0.inkBounds.intersects(crop) }
                guard kept.count != document.annotations.count else { return }
                document.annotations = StepBadges.renumbered(kept)
            }
        }
    }

    /// Drops the frame, leaving the document as it was, and goes back to the tool that was in use.
    func cancelCrop() {
        guard isCropping else { return }
        leaveCropTool()
    }

    private func leaveCropTool() {
        cropFrame = nil
        cropGesture = nil
        tool = toolBeforeCrop == .crop ? .arrow : toolBeforeCrop
    }

    /// Takes hold of a handle, the frame's middle or nothing where the drag began, and applies the drag to what it took
    /// hold of: resizing, moving, or making a new frame. A drag too small to make a frame leaves the one there was.
    private func dragCropFrame(from start: CGPoint, to end: CGPoint, pixelsPerPoint: CGFloat) {
        let bounds = canvas.bounds(of: document.imageSize)
        let ratio = cropAspect.ratio(of: document.imageSize)
        var gesture = cropGesture
        if gesture?.start != start {
            let frame = cropFrame.map { CropFrame(rect: $0, bounds: bounds, ratio: ratio) }
            let reach = Self.cropHandleReach * max(pixelsPerPoint, 0)
            gesture = CropGesture(start: start, frame: frame, grab: frame?.grab(at: start, tolerance: reach) ?? .outside)
            cropGesture = gesture
        }
        guard let gesture else { return }
        let delta = CGSize(width: end.x - start.x, height: end.y - start.y)
        switch (gesture.grab, gesture.frame) {
        case (.handle(let handle), let frame?):
            cropFrame = frame.resized(handle, by: delta).rect
        case (.inside, let frame?):
            cropFrame = frame.moved(by: delta).rect
        default:
            cropFrame = CropFrame.dragging(from: start, to: end, in: bounds, ratio: ratio)?.rect ?? gesture.frame?.rect
        }
    }

    /// The document to save, copy or compare, including text still being typed.
    func finishedDocument() -> MarkupDocument {
        commitText()
        return document
    }

    private func options(_ pixelsPerPoint: CGFloat, _ modifiers: MarkupModifiers) -> DrawingOptions {
        DrawingOptions(
            color: color, thickness: thickness, pixelsPerPoint: pixelsPerPoint, pointScale: pointScale, magnification: magnification,
            nextStep: StepBadges.nextNumber(in: document.annotations), snapsToAxis: modifiers.contains(.shift)
        )
    }

    private func removesStep(_ modifiers: MarkupModifiers) -> Bool {
        tool == .step && modifiers.contains(.option)
    }

    /// Takes the badge under `point` out and renumbers the ones after it, as one undo step.
    private func removeStep(at point: CGPoint) {
        guard let index = StepBadges.indexOfTopmost(at: point, in: document.annotations) else { return }
        edit {
            $0.apply {
                $0.annotations.remove(at: index)
                $0.annotations = StepBadges.renumbered($0.annotations)
            }
        }
    }

    /// `point` held inside what the current tool may reach: redaction and erasing work on pixels that exist, so they
    /// stop at the canvas; everything else may grow the canvas, but only so far as `CanvasInsets.limit` allows, which
    /// keeps a drag that leaves the window from asking for an enormous bitmap. A cropped picture is all there is to draw
    /// on: every tool stops at its edge, since whatever went past it would be cut away.
    private func limited(_ point: CGPoint) -> CGPoint {
        let size = document.imageSize
        let canvasBounds = canvas.bounds(of: size)
        let reach = CGFloat(CanvasInsets.limit(for: size))
        let allowed: CGRect
        if document.cropWithinCanvas != nil {
            allowed = document.outputBounds
        } else if tool == .redact || tool == .erase {
            allowed = canvasBounds
        } else {
            allowed = CGRect(origin: .zero, size: size).insetBy(dx: -reach, dy: -reach)
        }
        return CGPoint(x: min(max(point.x, allowed.minX), allowed.maxX), y: min(max(point.y, allowed.minY), allowed.maxY))
    }

    /// A new drag restarts the path. The highlighter keeps points at least `minimumStep` apart (one view point while
    /// dragging, so long strokes stay small in the JSON); other tools only need both ends.
    private func track(from start: CGPoint, to end: CGPoint, minimumStep: CGFloat) {
        if dragPoints.first != start { dragPoints = [start] }
        guard tool == .highlighter else {
            dragPoints = [start, end]
            return
        }
        if let last = dragPoints.last, last != end, hypot(end.x - last.x, end.y - last.y) >= minimumStep {
            dragPoints.append(end)
        }
    }

    // MARK: - Viewport Zoom & Pan

    func setZoom(_ scale: CGFloat, anchor: CGPoint? = nil, viewSize: CGSize? = nil) {
        let newZoom = min(max(scale, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        let effectiveViewSize = viewSize ?? lastViewportSize
        if let anchor, effectiveViewSize.width > 0, effectiveViewSize.height > 0, zoomScale > 0 {
            let viewCenter = CGPoint(x: effectiveViewSize.width / 2, y: effectiveViewSize.height / 2)
            let ratio = newZoom / zoomScale
            let candidatePan = CGSize(
                width: (anchor.x - viewCenter.x) - ((anchor.x - viewCenter.x) - panOffset.width) * ratio,
                height: (anchor.y - viewCenter.y) - ((anchor.y - viewCenter.y) - panOffset.height) * ratio
            )
            self.zoomScale = newZoom
            self.panOffset = clampedPanOffset(candidatePan, viewSize: effectiveViewSize)
        } else {
            let ratio = zoomScale > 0 ? newZoom / zoomScale : 1.0
            let candidatePan = CGSize(width: panOffset.width * ratio, height: panOffset.height * ratio)
            self.zoomScale = newZoom
            self.panOffset = effectiveViewSize.width > 0 ? clampedPanOffset(candidatePan, viewSize: effectiveViewSize) : candidatePan
        }
    }

    func magnify(by magnification: CGFloat, anchor: CGPoint? = nil, viewSize: CGSize? = nil) {
        let factor = max(1 + magnification, 0.1)
        setZoom(zoomScale * factor, anchor: anchor, viewSize: viewSize)
    }

    func zoomIn(viewSize: CGSize? = nil) {
        setZoom(zoomScale * Self.zoomStep, viewSize: viewSize)
    }

    func zoomOut(viewSize: CGSize? = nil) {
        setZoom(zoomScale / Self.zoomStep, viewSize: viewSize)
    }

    func resetZoom() {
        zoomScale = 1.0
        panOffset = .zero
    }

    func zoomToFitWidth(viewSize: CGSize? = nil, maximumScale: CGFloat = 1, margin: CGFloat = 24) {
        let vSize = viewSize ?? lastViewportSize
        guard vSize.width > 2 * margin, canvasSize.width > 0 else {
            resetZoom()
            return
        }
        let fit = ImageFit(imageSize: canvasSize, viewSize: vSize, maximumScale: maximumScale, margin: margin, origin: canvasOrigin)
        guard fit.baseScale > 0 else {
            resetZoom()
            return
        }
        let targetScale = (vSize.width - 2 * margin) / canvasSize.width
        let targetZoom = min(max(targetScale / fit.baseScale, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        self.zoomScale = targetZoom
        let renderedHeight = canvasSize.height * fit.baseScale * targetZoom
        let topPan = max((renderedHeight - (vSize.height - 2 * margin)) / 2, 0)
        self.panOffset = clampedPanOffset(CGSize(width: 0, height: topPan), viewSize: vSize)
    }

    func pan(by delta: CGSize, viewSize: CGSize? = nil) {
        let vSize = viewSize ?? lastViewportSize
        let candidate = CGSize(width: panOffset.width + delta.width, height: panOffset.height + delta.height)
        self.panOffset = vSize.width > 0 ? clampedPanOffset(candidate, viewSize: vSize) : candidate
    }

    private func clampedPanOffset(_ offset: CGSize, viewSize: CGSize) -> CGSize {
        guard viewSize.width > 0, viewSize.height > 0 else { return offset }
        if abs(zoomScale - 1.0) < 0.001 {
            let fit = ImageFit(imageSize: canvasSize, viewSize: viewSize, margin: 24, origin: canvasOrigin, zoomScale: 1.0, panOffset: .zero)
            if fit.frame.width <= viewSize.width && fit.frame.height <= viewSize.height {
                return .zero
            }
        }
        let fit = ImageFit(imageSize: canvasSize, viewSize: viewSize, margin: 24, origin: canvasOrigin, zoomScale: zoomScale, panOffset: .zero)
        let maxOverflowX = max((fit.frame.width - (viewSize.width - 48)) / 2, 0)
        let maxOverflowY = max((fit.frame.height - (viewSize.height - 48)) / 2, 0)
        let limitX = max(maxOverflowX, zoomScale > 1.0 ? viewSize.width * 0.25 : 0)
        let limitY = max(maxOverflowY, zoomScale > 1.0 ? viewSize.height * 0.25 : 0)
        return CGSize(
            width: min(max(offset.width, -limitX), limitX),
            height: min(max(offset.height, -limitY), limitY)
        )
    }

    /// Re-flattens the preview after a change to the history, which costs a full-resolution render. When that fails the
    /// last picture that could be made stays on screen with the canvas that goes with it, so the two never disagree.
    private func edit(_ change: (inout UndoStack) -> Void) {
        let before = history.document
        change(&history)
        guard history.document != before else { return }
        guard let rendered = Self.rendered(image, history.document, using: render) else { return }
        canvas = history.document.canvas
        canvasPreview = rendered.canvas
        preview = rendered.saved
        outputBounds = Self.effectiveOutputBounds(for: history.document)
    }

    /// The canvas with every annotation, and that canvas cut to the crop. The capture itself while there is nothing to
    /// draw (nor any padding) and nothing cropped; nil when rendering fails, which is logged since the annotations would
    /// otherwise vanish from the screen without a word.
    private static func rendered(
        _ image: CGImage, _ document: MarkupDocument, using render: (CGImage, MarkupDocument) -> CGImage?
    ) -> (canvas: CGImage, saved: CGImage)? {
        var uncropped = document
        uncropped.crop = nil
        uncropped.studioFrame = nil
        var canvas = image
        if !document.annotations.isEmpty {
            guard let flattened = render(image, uncropped) else {
                logger.error("Could not render \(document.annotations.count) annotations onto a \(image.width)×\(image.height) capture")
                return nil
            }
            canvas = flattened
        }
        var saved = canvas
        if let crop = document.cropWithinCanvas {
            guard let cut = MarkupRenderer.cut(canvas, to: crop, canvasBounds: uncropped.canvas.bounds(of: document.imageSize)) else {
                logger.error("Could not crop a \(canvas.width)×\(canvas.height) canvas to \(Int(crop.width))×\(Int(crop.height))")
                return nil
            }
            saved = cut
        }
        if let studio = document.studioFrame, studio.isActive {
            guard let studioImage = StudioFrameRenderer.render(saved, config: studio) else {
                return (canvas, saved)
            }
            saved = studioImage
        }
        return (canvas, saved)
    }

    private static func effectiveOutputBounds(for document: MarkupDocument) -> CGRect {
        let bounds = document.outputBounds
        if let studio = document.studioFrame, studio.isActive {
            let pad = CGFloat(max(0, studio.padding))
            return bounds.insetBy(dx: -pad, dy: -pad)
        }
        return bounds
    }

    private static let logger = Log.logger(category: "MarkupEditor")
}
