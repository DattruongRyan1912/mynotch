import AppKit
import SwiftUI

/// A soft band of light crossing the fill from left to right, over and over, as a Core Animation animation: the render server plays
/// it and SwiftUI does no work per frame. It used to be a `TimelineView(.animation)`, which evaluated its body, and so laid out the
/// notch's hosting view, 60 times a second for as long as the battery charged. The view is mounted only while the sweep should
/// run (see `BatteryGaugeMotion.isSweeping`), and it takes the animation away whenever it leaves its window.
struct ChargingSweep: NSViewRepresentable {
    let fillWidth: CGFloat

    func makeNSView(context: Context) -> ChargingSweepView {
        ChargingSweepView(fillWidth: fillWidth)
    }

    func updateNSView(_ view: ChargingSweepView, context: Context) {
        view.fillWidth = fillWidth
    }

    /// The fill's own size: the view paints inside whatever it is offered, and has no size of its own.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: ChargingSweepView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }
}

/// The view behind `ChargingSweep`: a gradient band on a layer of its own, clipped to the fill's rounded shape, with one repeating
/// animation of the band's position.
final class ChargingSweepView: NSView {
    static let animationKey = "chargingSweep"
    static let bandWidth: CGFloat = 70
    /// The band's brightest point, in the middle of it.
    static let peakOpacity: CGFloat = 0.25

    /// Clips the band to the fill's rounded shape. A layer of its own, so nothing here depends on what SwiftUI does to this view's layer.
    let clip = CALayer()
    let band = CAGradientLayer()
    private let now: () -> Date
    /// How many times the animation was added, for tests: it is added when the view comes into a window and again when the fill
    /// changes width, and never because of the passing of time.
    private(set) var animationStarts = 0

    /// How far the band travels: the fill's width, which follows the percent. A new one carries on from where the sweep is.
    var fillWidth: CGFloat {
        didSet {
            guard fillWidth != oldValue else { return }
            syncAnimation()
        }
    }

    init(fillWidth: CGFloat, now: @escaping () -> Date = Date.init) {
        self.fillWidth = fillWidth
        self.now = now
        super.init(frame: .zero)
        wantsLayer = true
        // The same corners as the fill behind it, which is a `RoundedRectangle` in its default, continuous style.
        clip.cornerRadius = BatteryGaugeLayout.fillRadius
        clip.cornerCurve = .continuous
        clip.masksToBounds = true
        // White at no opacity at both ends, rather than `clear`, which is transparent black and would leave a grey fringe.
        band.colors = [Self.white(0), Self.white(Self.peakOpacity), Self.white(0)]
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        clip.addSublayer(band)
        layer?.addSublayer(clip)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func white(_ alpha: CGFloat) -> CGColor {
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha)
    }

    /// Clicks and hovers belong to the SwiftUI view this sits in.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Whether the band is being swept across the fill.
    var isSweeping: Bool { band.animation(forKey: Self.animationKey) != nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clip.frame = bounds
        // Where the sweep begins, wholly outside the fill: the layer's own state, and what it shows while nothing animates it.
        band.bounds = CGRect(x: 0, y: 0, width: Self.bandWidth, height: bounds.height)
        band.position = CGPoint(x: -Self.bandWidth / 2, y: bounds.height / 2)
        CATransaction.commit()
    }

    /// A layer that left the window and came back may have lost its animation, and a hidden one has nothing to show.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncAnimation()
    }

    /// The band's centre travels from just outside the fill's left end to just outside its right end, once per `sweepPeriod`, at a
    /// steady pace and without end, and is at the wall clock's place in that sweep when the animation is added: so a sweep that
    /// starts again (a new width, a notch that comes back) carries on instead of jumping, and every display shows the same one.
    static func animation(fillWidth: CGFloat, phase: Double) -> CABasicAnimation {
        let sweep = CABasicAnimation(keyPath: "position.x")
        sweep.fromValue = -bandWidth / 2
        sweep.toValue = fillWidth + bandWidth / 2
        sweep.duration = BatteryGaugeMotion.sweepPeriod
        sweep.repeatCount = .infinity
        sweep.timeOffset = phase * BatteryGaugeMotion.sweepPeriod
        // Sixty frames a second, as the timeline it replaces was limited to, however fast the display is.
        sweep.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
        return sweep
    }

    private func syncAnimation() {
        guard window != nil else {
            band.removeAnimation(forKey: Self.animationKey)
            return
        }
        startSweep()
    }

    /// Begins the sweep at the wall clock's place in it, in place of one that is running.
    func startSweep() {
        let phase = BatteryGaugeMotion.sweepPhase(at: now().timeIntervalSinceReferenceDate)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        band.add(Self.animation(fillWidth: fillWidth, phase: phase), forKey: Self.animationKey)
        CATransaction.commit()
        animationStarts += 1
    }
}
