import AppKit
import NotchUI
import Observation

/// The translucent rectangle that shows where a drop would put the window. A borderless, click-through panel that never
/// takes the keyboard or activates MyNotch, above ordinary windows and below the notch.
final class SnapPreviewOverlay: NSPanel, SnapPreview {
    private var follower: CaptureHidingFollower?
    private var accentTask: Task<Void, Never>?

    /// Follows the hide-from-recording setting from the moment it exists, before it can ever be shown. It only exists
    /// while the tiles are open, so it is treated like the expanded notch: shown in recordings unless the user hides
    /// MyNotch always. The rectangle is in the notch's accent, set again when the accent changes (a layer keeps the colour
    /// it was given), and never otherwise.
    init(interface: NotchInterface = .shared) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Over the window being dragged, which is an ordinary window, and under the notch's own panel.
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]
        isMovable = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        let preview = PreviewView(accent: interface.accentRGB.nsColor)
        contentView = preview
        follower = CaptureHidingFollower(self, as: .toast, interface: interface)
        accentTask = Task { [weak preview] in
            for await accent in Observations({ interface.accentRGB }) {
                guard let preview else { return }
                preview.accent = accent.nsColor
            }
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(frame: CGRect) {
        setFrame(frame, display: true)
        orderFrontRegardless()
    }

    func hide() {
        orderOut(nil)
    }

    func dismiss() {
        follower?.stop()
        follower = nil
        accentTask?.cancel()
        accentTask = nil
        orderOut(nil)
        close()
    }
}

/// A tinted rounded rectangle with a thin edge.
private final class PreviewView: NSView {
    /// What the rectangle is tinted with: the fill and the edge are this colour, the edge stronger.
    var accent: NSColor {
        didSet {
            guard accent != oldValue else { return }
            tint()
        }
    }

    init(accent: NSColor) {
        self.accent = accent
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 2
        tint()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func tint() {
        layer?.backgroundColor = accent.withAlphaComponent(0.2).cgColor
        layer?.borderColor = accent.withAlphaComponent(0.7).cgColor
    }
}
