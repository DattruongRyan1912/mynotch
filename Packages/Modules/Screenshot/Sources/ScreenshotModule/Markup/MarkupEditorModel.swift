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
/// preview. Gesture positions arrive already converted to image pixels, so the view only handles layout.
@Observable final class MarkupEditorModel {
    let image: CGImage
    private(set) var tool: MarkupTool = .arrow
    var color: RGBAColor = .red
    var thickness: StrokeThickness = .medium
    /// The shape under the pointer during a drag, drawn live over the preview.
    private(set) var draft: Annotation?
    var text: TextDraft?
    /// The capture with every committed annotation burned in, as it will be saved.
    private(set) var preview: CGImage
    private var history: UndoStack
    @ObservationIgnored private var dragPoints: [CGPoint] = []

    /// `document` reopens earlier markup; it must belong to `image`.
    init(image: CGImage, document: MarkupDocument? = nil) {
        self.image = image
        let document = document ?? MarkupDocument(imageSize: CGSize(width: image.width, height: image.height))
        history = UndoStack(document)
        preview = Self.flattened(image, document)
    }

    var document: MarkupDocument { history.document }
    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }
    /// The size of the text being typed, in image pixels.
    var textFontSize: CGFloat { thickness.fontSize * (text?.pixelsPerPoint ?? 1) }

    func select(_ tool: MarkupTool) {
        commitText()
        self.tool = tool
    }

    /// `start` and `end` are image pixels; `pixelsPerPoint` converts the view-sized thickness into pixels.
    func dragChanged(from start: CGPoint, to end: CGPoint, pixelsPerPoint: CGFloat) {
        guard tool != .text else { return }
        track(from: start, to: end, minimumStep: pixelsPerPoint)
        draft = tool.annotation(through: dragPoints, color: color, thickness: thickness, pixelsPerPoint: pixelsPerPoint)
    }

    /// Commits the drawn shape, or for the text tool starts typing where the drag began.
    func dragEnded(from start: CGPoint, to end: CGPoint, pixelsPerPoint: CGFloat) {
        defer {
            dragPoints = []
            draft = nil
        }
        guard tool != .text else {
            commitText()
            text = TextDraft(origin: start, pixelsPerPoint: pixelsPerPoint)
            return
        }
        track(from: start, to: end, minimumStep: 0)
        guard let annotation = tool.annotation(through: dragPoints, color: color, thickness: thickness, pixelsPerPoint: pixelsPerPoint) else { return }
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
        preview = Self.flattened(image, history.document)
    }

    /// The preview falls back to the plain capture when rendering fails; that is logged, since the annotations
    /// would otherwise vanish from the screen without a word.
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
