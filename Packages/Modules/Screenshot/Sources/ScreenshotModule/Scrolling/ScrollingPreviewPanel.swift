import AppKit
import CoreGraphics
import NotchUI
import SwiftUI

@MainActor
protocol ScrollingPreviewPresenting: AnyObject {
    func show(
        canvas: CGImage,
        frameCount: Int,
        avoidingRect: CGRect?,
        onFinish: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    )
    func update(canvas: CGImage, frameCount: Int)
    func hide()
}

@MainActor
final class ScrollingPreviewModel: ObservableObject {
    @Published var canvas: CGImage
    @Published var frameCount: Int
    let onFinish: @MainActor () -> Void
    let onCancel: @MainActor () -> Void

    init(
        canvas: CGImage,
        frameCount: Int,
        onFinish: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        self.canvas = canvas
        self.frameCount = frameCount
        self.onFinish = onFinish
        self.onCancel = onCancel
    }
}

struct ScrollingPreviewHUDView: View {
    @ObservedObject var model: ScrollingPreviewModel

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack(spacing: 6) {
                ScreenshotSpinnerView()
                Text("Đang chụp cuộn")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NotchTokens.primaryText)
                Spacer()
                Text("\(model.canvas.width)×\(model.canvas.height)px")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(NotchTokens.secondaryText)
            }
            .padding(.horizontal, 4)

            // Live Canvas Preview Frame
            ZStack {
                Color.black.opacity(0.6)
                Image(decorative: model.canvas, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 168, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .frame(width: 176, height: 186)
            .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            }

            // Footer with Frame count & Actions
            HStack(spacing: 8) {
                Text("\(model.frameCount) đoạn")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(NotchTokens.secondaryText)
                Spacer()
                Button("Huỷ (⎋)", action: model.onCancel)
                    .buttonStyle(ScrollingHUDButtonStyle(isPrimary: false))
                    .help("Huỷ phiên chụp cuộn")
                Button("Xong (⏎)", action: model.onFinish)
                    .buttonStyle(ScrollingHUDButtonStyle(isPrimary: true))
                    .help("Hoàn tất và lưu ảnh cuộn")
            }
            .padding(.horizontal, 4)
        }
        .padding(10)
        .frame(width: 196)
        .background(
            Color(red: 0.035, green: 0.035, blue: 0.043).opacity(0.96),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(red: 0.153, green: 0.153, blue: 0.165), lineWidth: 1)
        }
        .notchOnDarkBackground()
        .fixedSize()
    }
}

private struct ScrollingHUDButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(NotchTokens.primaryText)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isPrimary ? NotchTokens.accent.opacity(configuration.isPressed ? 0.7 : 0.95) : Color.white.opacity(configuration.isPressed ? 0.22 : 0.12))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isPrimary ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .focusable(false)
    }
}

final class ScrollingPreviewPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        // Crucial: sharingType = .none ensures ScreenCaptureKit will NOT capture this preview window into the screenshot
        sharingType = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        title = "Đang chụp cuộn"
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ScrollingPreviewHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class SystemScrollingPreviewWindow: ScrollingPreviewPresenting {
    private var panel: ScrollingPreviewPanel?
    private var model: ScrollingPreviewModel?

    func show(
        canvas: CGImage,
        frameCount: Int,
        avoidingRect: CGRect?,
        onFinish: @escaping @MainActor () -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
        let model = ScrollingPreviewModel(
            canvas: canvas,
            frameCount: frameCount,
            onFinish: onFinish,
            onCancel: onCancel
        )
        self.model = model

        let view = ScrollingPreviewHUDView(model: model)
        let hostingView = ScrollingPreviewHostingView(rootView: AnyView(view))

        let fittingSize = hostingView.fittingSize
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        // Default: Bottom-right, 24px margin
        var originX = visibleFrame.maxX - fittingSize.width - 24
        let originY = visibleFrame.minY + 24

        // If avoidingRect overlaps with the bottom-right corner, move to bottom-left
        if let avoidingRect {
            let panelCandidateRect = CGRect(x: originX, y: originY, width: fittingSize.width, height: fittingSize.height)
            if panelCandidateRect.intersects(avoidingRect) {
                originX = visibleFrame.minX + 24
            }
        }

        let panelRect = CGRect(x: originX, y: originY, width: fittingSize.width, height: fittingSize.height)
        let panel = ScrollingPreviewPanel(contentRect: panelRect)
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func update(canvas: CGImage, frameCount: Int) {
        guard let model, let panel else { return }
        model.canvas = canvas
        model.frameCount = frameCount
        if let hostingView = panel.contentView as? ScrollingPreviewHostingView {
            let newSize = hostingView.fittingSize
            if abs(panel.frame.height - newSize.height) > 2 || abs(panel.frame.width - newSize.width) > 2 {
                panel.setContentSize(newSize)
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }
}
