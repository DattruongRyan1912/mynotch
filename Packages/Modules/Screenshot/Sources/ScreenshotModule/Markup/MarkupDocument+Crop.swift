import CoreGraphics

nonisolated extension MarkupDocument {
    /// Whether flattening changes the capture at all: a plain document is the capture as it was taken.
    var hasEdits: Bool { !annotations.isEmpty || crop != nil }

    /// The crop where it overlaps `canvas` (the capture and the padding the annotations grew), or nil when nothing is
    /// cropped or the crop does not reach the canvas. A damaged file or an undone annotation can leave a crop out there;
    /// it is then ignored instead of producing an empty picture.
    func cropWithinCanvas(_ canvas: CanvasInsets) -> CGRect? {
        guard let crop else { return nil }
        let visible = crop.standardized.intersection(canvas.bounds(of: imageSize))
        return visible.isNull || visible.width < 1 || visible.height < 1 ? nil : visible
    }

    var cropWithinCanvas: CGRect? { cropWithinCanvas(canvas) }

    /// The part of annotation space the saved picture shows: the crop, or else the capture with its padding.
    func outputBounds(in canvas: CanvasInsets) -> CGRect {
        cropWithinCanvas(canvas) ?? canvas.bounds(of: imageSize)
    }

    var outputBounds: CGRect { outputBounds(in: canvas) }
}
