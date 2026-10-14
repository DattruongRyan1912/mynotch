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

/// The markup editor's state: tool choices, the shape being drawn, inline text, undo history and the flattened
/// preview. Gesture positions arrive already converted to annotation pixels (origin at the capture's top-left, so
/// they may be negative or past its far edges), so the view only handles layout.
@Observable final class MarkupEditorModel {
    let image: CGImage
    /// The capture's pixels per point, for the ruler's label.
    let pointScale: CGFloat
    private(set) var tool: MarkupTool = .arrow
    var color: RGBAColor = .red
    var thickness: StrokeThickness = .medium
    var magnification: CGFloat = 2
    /// The shape under the pointer during a drag, drawn live over the preview.
    private(set) var draft: Annotation?
    var text: TextDraft?
    /// The canvas with every committed annotation burned in, as it will be saved.
    private(set) var preview: CGImage
    /// How far the canvas reaches past the capture, from the annotations that stick out.
    private(set) var canvas: CanvasInsets
    private var history: UndoStack
    @ObservationIgnored private var dragPoints: [CGPoint] = []

    /// `document` reopens earlier markup; it must belong to `image`. `pointScale` is the capture's pixels per point,
    /// and `canvasFill` is what padding is filled with; it replaces the document's, which is not saved.
    init(image: CGImage, document: MarkupDocument? = nil, pointScale: CGFloat = 1, canvasFill: CanvasFill = .standard) {
        self.image = image
        self.pointScale = pointScale
        var document = document ?? MarkupDocument(imageSize: CGSize(width: image.width, height: image.height))
        document.canvasFill = canvasFill
        history = UndoStack(document)
        canvas = document.canvas
        preview = Self.flattened(image, document)
    }

    var document: MarkupDocument { history.document }
    var canvasSize: CGSize { canvas.size(of: document.imageSize) }
    /// The annotation-space point at the canvas's top-left corner.
    var canvasOrigin: CGPoint { CGPoint(x: -canvas.left, y: -canvas.top) }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    /// The size of the text being typed, in image pixels.
    var textFontSize: CGFloat { thickness.fontSize * (text?.pixelsPerPoint ?? 1) }

    func select(_ tool: MarkupTool) {
        commitText()
        self.tool = tool
    }

    /// `start` and `end` are annotation pixels; `pixelsPerPoint` converts the view-sized thickness into pixels. A
    /// drawing tool may be dragged past the capture's edge, which grows the canvas when the shape is committed.
    func dragChanged(from start: CGPoint, to end: CGPoint, pixelsPerPoint: CGFloat, modifiers: MarkupModifiers = []) {
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

    func cancelText() {
        text = nil
    }

    func undo() {
        edit { $0.undo() }
    }

    func redo() {
        edit { $0.redo() }
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
    /// keeps a drag that leaves the window from asking for an enormous bitmap.
    private func limited(_ point: CGPoint) -> CGPoint {
        let size = document.imageSize
        let reach = CGFloat(CanvasInsets.limit(for: size))
        let allowed = tool == .redact || tool == .erase ? canvas.bounds(of: size) : CGRect(origin: .zero, size: size).insetBy(dx: -reach, dy: -reach)
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

    /// Re-flattens the preview after a change to the history, which costs a full-resolution render.
    private func edit(_ change: (inout UndoStack) -> Void) {
        let before = history.document
        change(&history)
        guard history.document != before else { return }
        canvas = history.document.canvas
        preview = Self.flattened(image, history.document)
    }

    /// The preview falls back to the plain capture when rendering fails; that is logged, since the annotations
    /// would otherwise vanish from the screen without a word. Without annotations the canvas has not grown either.
    private static func flattened(_ image: CGImage, _ document: MarkupDocument) -> CGImage {
        guard !document.annotations.isEmpty else { return image }
        guard let flattened = MarkupRenderer.flatten(image, document) else {
            logger.error("Could not render \(document.annotations.count) annotations onto a \(image.width)×\(image.height) capture")
            return image
        }
        return flattened
    }

    private static let logger = Log.logger(category: "MarkupEditor")
}
