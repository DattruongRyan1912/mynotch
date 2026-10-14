import AppKit
import SwiftUI

/// Dims and restores its content over and over while `isActive`, the way a repeating pulse symbol effect does, but as a Core Animation
/// animation: the render server runs it and SwiftUI does no work per frame. `symbolEffect(.pulse, options: .repeating)` redraws the
/// symbol at the display's refresh rate for as long as it runs, which keeps the notch's whole hosting view laying out and committing
/// continuously. The content is drawn once, in a hosting view of its own, and again only when it changes.
public struct NotchPulse<Content: View>: NSViewRepresentable {
    /// Opacity at the dimmest point of a pulse; what a repeating pulse symbol effect reaches, measured offscreen.
    public static var dimmedOpacity: Float { 0.3 }
    /// Time from full to dimmed, and again from dimmed to full: the symbol effect's period is 2 s.
    public static var halfPeriod: CFTimeInterval { 1.0 }

    let isActive: Bool
    let content: Content

    public init(isActive: Bool, @ViewBuilder content: () -> Content) {
        self.isActive = isActive
        self.content = content()
    }

    public func makeNSView(context: Context) -> NotchPulseView<Content> {
        NotchPulseView(content: content)
    }

    public func updateNSView(_ view: NotchPulseView<Content>, context: Context) {
        view.host.rootView = content
        // Not while the notch is hidden: nothing would be seen, and the render server would still carry the animation.
        view.setPulsing(isActive && context.environment.notchIsOnScreen)
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NotchPulseView<Content>, context: Context) -> CGSize? {
        view.host.intrinsicContentSize
    }
}

extension View {
    /// Pulses the view while `isActive` without making SwiftUI redraw it every frame; see `NotchPulse`.
    public func notchPulse(isActive: Bool) -> some View {
        NotchPulse(isActive: isActive) { self }.allowsHitTesting(false)
    }
}

/// The view behind `NotchPulse`: hosts the content and pulses the opacity of the hosting view's own layer, so the opacity
/// SwiftUI sets on this view (a transition, a fade) never fights the animation.
public final class NotchPulseView<Content: View>: NSView {
    static var animationKey: String { "notchPulse" }

    let host: NSHostingView<Content>

    init(content: Content) {
        host = NSHostingView(rootView: content)
        super.init(frame: .zero)
        // Only the content's own size: `NotchPulse` reports it, and `layout()` sets the frame.
        host.sizingOptions = [.intrinsicContentSize]
        addSubview(host)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Clicks and hovers belong to the SwiftUI view this sits in.
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    public override func layout() {
        super.layout()
        host.frame = bounds
    }

    private var wantsPulse = false

    var isPulsing: Bool { host.layer?.animation(forKey: Self.animationKey) != nil }

    func setPulsing(_ pulsing: Bool) {
        wantsPulse = pulsing
        syncAnimation()
    }

    /// A layer that left the window and came back may have lost its animation.
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncAnimation()
    }

    private func syncAnimation() {
        guard wantsPulse != isPulsing, let layer = host.layer else { return }
        guard wantsPulse else {
            layer.removeAnimation(forKey: Self.animationKey)
            return
        }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = NotchPulse<Content>.dimmedOpacity
        pulse.duration = NotchPulse<Content>.halfPeriod
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(pulse, forKey: Self.animationKey)
    }
}
