import AppKit
import SwiftUI

/// Draws markup on a capture, and past its edges: the canvas grows to hold what sticks out. The host owns the window
/// and decides what Lưu, Copy and Huỷ do; each callback receives the document including text still being typed, so
/// the host can flatten it with `MarkupRenderer` or compare it with what was last saved. The host builds the model
/// once and keeps it, so the preview is not rendered again whenever SwiftUI recreates this view.
struct MarkupEditorView: View {
    let model: MarkupEditorModel
    @FocusState private var isTyping: Bool
    @State private var isSpaceHeld = false
    @State private var dragStartPan: CGSize?
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
                let fit = ImageFit(
                    imageSize: model.canvasSize,
                    viewSize: proxy.size,
                    maximumScale: 1 / displayScale,
                    margin: Self.margin,
                    origin: model.canvasOrigin,
                    zoomScale: model.zoomScale,
                    panOffset: model.panOffset
                )
                ZStack {
                    canvas(fit: fit)
                    MarkupTrackpadEventView(
                        onMagnify: { magnification, anchor, viewSize in
                            model.magnify(by: magnification, anchor: anchor, viewSize: viewSize)
                        },
                        onScroll: { delta, viewSize in
                            model.pan(by: delta, viewSize: viewSize)
                        },
                        isSpaceHeld: $isSpaceHeld,
                        canCaptureSpace: model.text == nil
                    )
                }
                .onAppear {
                    model.lastViewportSize = proxy.size
                }
                .onChange(of: proxy.size) { _, newSize in
                    model.lastViewportSize = newSize
                }
            }
            .clipped()
            .background(Color(nsColor: .underPageBackgroundColor))
        }
        .frame(minWidth: 900, minHeight: 440)
    }

    /// Points kept free around the canvas, so a drag can leave the capture and grow the canvas.
    private static let margin: CGFloat = 24

    private func canvas(fit: ImageFit) -> some View {
        let draft = model.draft
        let cropFrame = model.cropFrame
        return ZStack(alignment: .topLeading) {
            // The gesture belongs to the picture layer only, so clicks inside the text field edit its text.
            ZStack(alignment: .topLeading) {
                Image(decorative: model.displayedPreview, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: fit.frame.width, height: fit.frame.height)
                    .offset(x: fit.frame.minX, y: fit.frame.minY)
                Canvas { context, _ in
                    Self.draw(draft, in: &context, fit: fit)
                    if let cropFrame { Self.drawCropFrame(cropFrame, in: &context, fit: fit) }
                }
                    // Shows the highlighter's multiply blend against the image while dragging.
                    .blendMode(model.tool == .highlighter ? .multiply : .normal)
                    .allowsHitTesting(false)
            }
            .frame(width: fit.viewSize.width, height: fit.viewSize.height, alignment: .topLeading)
            .contentShape(.rect)
            .gesture(drawingGesture(fit: fit))
            .pointerStyle(isSpaceHeld ? .default : (model.tool == .text ? .horizontalText : .rectSelection))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ảnh chụp đang sửa")
            if let text = model.text {
                textField(at: fit.viewPoint(fromImage: text.origin), fontSize: model.textFontSize * fit.scale)
            }
        }
        .frame(width: fit.viewSize.width, height: fit.viewSize.height, alignment: .topLeading)
    }

    /// Points are not clamped to the picture: the model decides how far each tool may reach beyond it.
    private func drawingGesture(fit: ImageFit) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if isSpaceHeld {
                    let initial = dragStartPan ?? model.panOffset
                    if dragStartPan == nil { dragStartPan = initial }
                    let delta = CGSize(
                        width: value.translation.width,
                        height: value.translation.height
                    )
                    model.pan(
                        by: CGSize(
                            width: initial.width + delta.width - model.panOffset.width,
                            height: initial.height + delta.height - model.panOffset.height
                        ),
                        viewSize: fit.viewSize
                    )
                    return
                }
                guard fit.scale > 0 else { return }
                model.dragChanged(
                    from: fit.imagePoint(fromView: value.startLocation, clamped: false),
                    to: fit.imagePoint(fromView: value.location, clamped: false),
                    pixelsPerPoint: 1 / fit.scale, modifiers: Self.heldModifiers
                )
            }
            .onEnded { value in
                if isSpaceHeld {
                    dragStartPan = nil
                    return
                }
                guard fit.scale > 0 else { return }
                model.dragEnded(
                    from: fit.imagePoint(fromView: value.startLocation, clamped: false),
                    to: fit.imagePoint(fromView: value.location, clamped: false),
                    pixelsPerPoint: 1 / fit.scale, modifiers: Self.heldModifiers
                )
                if model.text != nil { isTyping = true }
            }
    }

    /// ⇧ and ⌥ as they are held now, read when the pointer moves or the button is released.
    private static var heldModifiers: MarkupModifiers {
        let flags = NSEvent.modifierFlags
        var held: MarkupModifiers = []
        if flags.contains(.shift) { held.insert(.shift) }
        if flags.contains(.option) { held.insert(.option) }
        return held
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

    /// The shape being dragged, drawn by the renderer itself so it matches the saved result. Redaction, erasing and
    /// the lens need the pixels underneath, so they show as a dashed outline until the drag ends and the preview
    /// applies them. What is drawn beyond the picture is kept: committing it grows the canvas.
    private static func draw(_ draft: Annotation?, in context: inout GraphicsContext, fit: ImageFit) {
        guard let draft else { return }
        switch draft {
        case .redact(let rect), .erase(let rect):
            outline(Path(fit.viewRect(fromImage: rect)), in: &context)
        case .magnifier(let center, let radius, _, _):
            outline(Path(ellipseIn: fit.viewRect(fromImage: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))), in: &context)
        default:
            context.withCGContext { cgContext in
                let origin = fit.viewPoint(fromImage: .zero)
                cgContext.translateBy(x: origin.x, y: origin.y)
                cgContext.scaleBy(x: fit.scale, y: fit.scale)
                MarkupRenderer.draw(draft, in: cgContext)
            }
        }
    }

    /// The crop frame over the picture: everything outside it dimmed, thirds to line things up by, and a handle on each
    /// corner and edge. Where a handle sits is what `CropFrame.grab` takes hold of.
    private static func drawCropFrame(_ frame: CGRect, in context: inout GraphicsContext, fit: ImageFit) {
        let rect = fit.viewRect(fromImage: frame)
        var dimmed = Path(fit.frame)
        dimmed.addRect(rect)
        context.fill(dimmed, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
        var thirds = Path()
        for step in [1.0 / 3, 2.0 / 3] {
            thirds.move(to: CGPoint(x: rect.minX + rect.width * step, y: rect.minY))
            thirds.addLine(to: CGPoint(x: rect.minX + rect.width * step, y: rect.maxY))
            thirds.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * step))
            thirds.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * step))
        }
        context.stroke(thirds, with: .color(.white.opacity(0.35)), lineWidth: 1)
        context.stroke(Path(rect), with: .color(.white), lineWidth: 1.5)
        for handle in CropHandle.allCases {
            let point = handle.point(in: rect)
            let square = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            context.fill(Path(square), with: .color(.white))
            context.stroke(Path(square), with: .color(.black.opacity(0.6)), lineWidth: 1)
        }
    }

    private static func outline(_ path: Path, in context: inout GraphicsContext) {
        context.fill(path, with: .color(.black.opacity(0.35)))
        context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }
}

struct MarkupTrackpadEventView: NSViewRepresentable {
    let onMagnify: (CGFloat, CGPoint, CGSize) -> Void
    let onScroll: (CGSize, CGSize) -> Void
    @Binding var isSpaceHeld: Bool
    let canCaptureSpace: Bool

    func makeNSView(context: Context) -> EventTrackingNSView {
        let view = EventTrackingNSView()
        view.onMagnify = onMagnify
        view.onScroll = onScroll
        view.onSpaceChange = { [weak view] isHeld in
            guard view != nil else { return }
            DispatchQueue.main.async {
                if canCaptureSpace {
                    self.isSpaceHeld = isHeld
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: EventTrackingNSView, context: Context) {
        nsView.onMagnify = onMagnify
        nsView.onScroll = onScroll
    }
}

final class EventTrackingNSView: NSView {
    var onMagnify: ((CGFloat, CGPoint, CGSize) -> Void)?
    var onScroll: ((CGSize, CGSize) -> Void)?
    var onSpaceChange: ((Bool) -> Void)?
    nonisolated(unsafe) private var eventMonitor: Any?

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        guard let window else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel, .keyDown, .keyUp]) { [weak self] event in
            guard let self, self.window === window, window.isKeyWindow else { return event }
            let pointInWindow = event.locationInWindow
            let pointInView = self.convert(pointInWindow, from: nil)
            let isInside = self.bounds.contains(pointInView)

            switch event.type {
            case .magnify:
                guard isInside else { return event }
                self.onMagnify?(event.magnification, pointInView, self.bounds.size)
                return nil
            case .scrollWheel:
                guard isInside else { return event }
                if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
                    let mag = event.scrollingDeltaY * 0.01
                    self.onMagnify?(mag, pointInView, self.bounds.size)
                    return nil
                } else {
                    let dx = event.scrollingDeltaX
                    let dy = event.scrollingDeltaY
                    if abs(dx) > 0.01 || abs(dy) > 0.01 {
                        self.onScroll?(CGSize(width: dx, height: dy), self.bounds.size)
                        return nil
                    }
                }
            case .keyDown:
                if event.keyCode == 49 && !event.isARepeat {
                    self.onSpaceChange?(true)
                }
            case .keyUp:
                if event.keyCode == 49 {
                    self.onSpaceChange?(false)
                }
            default:
                break
            }
            return event
        }
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
}
