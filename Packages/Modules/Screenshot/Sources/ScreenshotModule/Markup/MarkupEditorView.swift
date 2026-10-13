import SwiftUI

/// Draws markup on a capture. The host owns the window and decides what Lưu, Copy and Huỷ do; each callback receives
/// the document including text still being typed, so the host can flatten it with `MarkupRenderer` or compare it
/// with what was last saved. The host builds the model once and keeps it, so the preview is not rendered again
/// whenever SwiftUI recreates this view.
struct MarkupEditorView: View {
    let model: MarkupEditorModel
    @FocusState private var isTyping: Bool
    @Environment(\.displayScale) private var displayScale
    let onSave: (MarkupDocument) -> Void
    let onCopy: (MarkupDocument) -> Void
    let onCancel: (MarkupDocument) -> Void

    var body: some View {
        VStack(spacing: 0) {
            MarkupToolbar(
                model: model,
                onCancel: { onCancel(model.finishedDocument()) },
                onCopy: { onCopy(model.finishedDocument()) },
                onSave: { onSave(model.finishedDocument()) }
            )
            Divider()
            GeometryReader { proxy in
                // At most one device pixel per image pixel, so small captures are not blown up into a blur.
                canvas(fit: ImageFit(imageSize: model.document.imageSize, viewSize: proxy.size, maximumScale: 1 / displayScale))
            }
            .background(Color(nsColor: .underPageBackgroundColor))
        }
        .frame(minWidth: 780, minHeight: 440)
    }

    private func canvas(fit: ImageFit) -> some View {
        let draft = model.draft
        return ZStack(alignment: .topLeading) {
            // The gesture belongs to the picture layer only, so clicks inside the text field edit its text.
            ZStack(alignment: .topLeading) {
                Image(decorative: model.preview, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: fit.frame.width, height: fit.frame.height)
                    .offset(x: fit.frame.minX, y: fit.frame.minY)
                Canvas { context, _ in Self.draw(draft, in: &context, fit: fit) }
                    // Shows the highlighter's multiply blend against the image while dragging.
                    .blendMode(model.tool == .highlighter ? .multiply : .normal)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(.rect)
            .gesture(drawingGesture(fit: fit))
            .pointerStyle(model.tool == .text ? .horizontalText : .rectSelection)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ảnh chụp đang sửa")
            if let text = model.text {
                textField(at: fit.viewPoint(fromImage: text.origin), fontSize: model.textFontSize * fit.scale)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func drawingGesture(fit: ImageFit) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard fit.scale > 0 else { return }
                model.dragChanged(
                    from: fit.imagePoint(fromView: value.startLocation), to: fit.imagePoint(fromView: value.location),
                    pixelsPerPoint: 1 / fit.scale
                )
            }
            .onEnded { value in
                guard fit.scale > 0 else { return }
                model.dragEnded(
                    from: fit.imagePoint(fromView: value.startLocation), to: fit.imagePoint(fromView: value.location),
                    pixelsPerPoint: 1 / fit.scale
                )
                if model.text != nil { isTyping = true }
            }
    }

    /// Return adds the text, Esc drops it; clicking elsewhere or switching tools also adds it.
    private func textField(at origin: CGPoint, fontSize: CGFloat) -> some View {
        TextField("Chữ", text: textBinding, prompt: Text("Nhập chữ"))
            .textFieldStyle(.plain)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(Color(model.color))
            .fixedSize()
            .frame(minWidth: 40, alignment: .leading)
            .overlay {
                Rectangle()
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .padding(-2)
            }
            .offset(x: origin.x, y: origin.y)
            .focused($isTyping)
            // Focus can only move to the field once it exists; later placements reuse it.
            .onAppear { isTyping = true }
            .onSubmit { model.commitText() }
            .onExitCommand { model.cancelText() }
    }

    private var textBinding: Binding<String> {
        Binding(get: { model.text?.string ?? "" }, set: { model.text?.string = $0 })
    }

    /// The shape being dragged, drawn by the renderer itself so it matches the saved result. Redaction needs the
    /// pixels underneath, so it shows as a dashed box until the drag ends and the preview pixelates it.
    private static func draw(_ draft: Annotation?, in context: inout GraphicsContext, fit: ImageFit) {
        guard let draft else { return }
        // A drag may leave the picture; what is drawn outside it would not be saved.
        context.clip(to: Path(fit.frame))
        if case .redact(let rect) = draft {
            let path = Path(fit.viewRect(fromImage: rect))
            context.fill(path, with: .color(.black.opacity(0.35)))
            context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            return
        }
        context.withCGContext { cgContext in
            cgContext.translateBy(x: fit.frame.minX, y: fit.frame.minY)
            cgContext.scaleBy(x: fit.scale, y: fit.scale)
            MarkupRenderer.draw(draft, in: cgContext)
        }
    }
}
