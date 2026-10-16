import AppKit
import NotchUI
import SwiftUI

/// How big the cat is drawn on one display: a whole number of device pixels to every pixel of the sprite, so the pixels stay square and
/// sharp, as many as make the cat fill most of the notch's height.
nonisolated struct SpriteMetrics: Equatable, Sendable {
    /// What share of the row's height the cat may take.
    static let fill: CGFloat = 0.8
    /// Space between the cat's feet and the bottom of the row, in points.
    static let floor: CGFloat = 2

    /// Device pixels to a pixel of the sprite.
    let pixelScale: Int
    let backingScale: CGFloat

    init(rowHeight: CGFloat, backingScale: CGFloat) {
        self.backingScale = max(backingScale, 1)
        pixelScale = max(Int((Self.fill * rowHeight * self.backingScale / CGFloat(CatArt.height)).rounded(.down)), 1)
    }

    /// One sprite pixel, in points.
    var step: CGFloat { CGFloat(pixelScale) / backingScale }

    var size: CGSize { CGSize(width: CGFloat(CatArt.width) * step, height: CGFloat(CatArt.height) * step) }
}

/// One wing's view of the cat. It owns a layer with the cat's picture on it and hands everything that moves to Core Animation: the
/// frames are one keyframe animation of the layer's `contentsRect` along a strip of pictures, the walk is another of its position, and
/// nothing is redrawn or laid out by SwiftUI while either runs. It takes both away the moment it leaves its window.
final class CatSpriteView: NSView {
    enum Role: Equatable {
        case leading, trailing
    }

    static let framesKey = "catFrames"
    static let walkKey = "catWalk"
    /// The frame rate the render server is asked to hold the cat's animations to, whatever the display can do.
    static let frameRateCeiling: Float = 24

    let role: Role
    private(set) weak var stage: CatStage?
    /// The picture. Anchored at its bottom left corner, so its position is the place of its left foot.
    let sprite = CALayer()

    init(stage: CatStage, role: Role) {
        self.stage = stage
        self.role = role
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        sprite.anchorPoint = .zero
        sprite.contentsGravity = .resize
        // Nearest neighbour both ways: the sprite is drawn at a whole number of device pixels to its pixel and any other filter smears it.
        sprite.magnificationFilter = .nearest
        sprite.minificationFilter = .nearest
        sprite.isHidden = true
        layer?.addSublayer(sprite)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Geometry

    /// The wing's frame in its window's coordinates.
    var windowFrame: CGRect { convert(bounds, to: nil) }

    /// The wing's frame on the screen; nil outside a window.
    var screenFrame: CGRect? { window?.convertToScreen(windowFrame) }

    /// A test's own backing scale, since a window that is never shown has whatever its machine's screens have.
    var backingScaleOverride: CGFloat?

    var metrics: SpriteMetrics {
        SpriteMetrics(rowHeight: bounds.height, backingScale: backingScaleOverride ?? window?.backingScaleFactor ?? 2)
    }

    /// Whether anything is animating on the layer.
    var isAnimating: Bool { !(sprite.animationKeys() ?? []).isEmpty }

    /// Where the cat is drawn: false when it has been taken away.
    var isShowingCat: Bool { !sprite.isHidden }

    override func layout() {
        super.layout()
        stage?.hostDidMove(self)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        stage?.hostDidMove(self)
    }

    /// A view that left its window and came back was never taken off the stage in between, and a layer that left a window may have lost
    /// its animations.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stage?.detach(self)
        } else {
            stage?.attach(self)
        }
    }

    // MARK: Clicks

    /// Only the cat takes clicks, so the rest of the wing opens the notch as it always did. It is hit where the cat is drawn at this
    /// moment, which on a walk is not where the layer's value says.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !sprite.isHidden, let superview else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        let drawn = (sprite.presentation() ?? sprite).frame.insetBy(dx: -3, dy: -3)
        return drawn.contains(local) ? self : nil
    }

    /// The panel never becomes active, so the first click has to be taken for what it is.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }

    /// A click on the cat is a stroke, and goes no further: it does not reach the notch's own tap, which would open it.
    override func mouseDown(with event: NSEvent) {
        stage?.catWasClicked()
    }

    // MARK: Showing

    /// Plays `plan` along `lane` from `elapsed` seconds into it. The lane is in the window's coordinates, and so are the cat's places on
    /// it; the layer's are this view's.
    func show(plan: CatPlan, lane: WalkLane, elapsed: TimeInterval) {
        guard isNeeded(on: lane) else {
            stopShowing()
            return
        }
        let metrics = metrics
        let strip = CatSheets.shared.strip(for: plan.pose, facing: plan.facing)
        let animation = CatArt.animation(for: plan.pose)
        let origin = windowFrame.minX
        let from = aligned(lane.x(at: plan.from) - origin, metrics)
        let to = aligned(lane.x(at: plan.to) - origin, metrics)
        let moves = from != to

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        prepare(strip: strip, lane: lane, metrics: metrics)
        sprite.removeAllAnimations()
        let rate = max(plan.fpsScale, 0.1)
        sprite.add(
            Self.framesAnimation(strip: strip, duration: animation.duration / rate, elapsed: elapsed, fps: animation.fps * rate),
            forKey: Self.framesKey
        )
        if moves {
            let walk = Self.walkAnimation(from: from, to: to, step: metrics.step, duration: plan.duration, elapsed: elapsed)
            sprite.add(walk, forKey: Self.walkKey)
            sprite.position = CGPoint(x: Self.lastValue(of: walk), y: SpriteMetrics.floor)
        } else {
            sprite.position = CGPoint(x: from, y: SpriteMetrics.floor)
        }
        CATransaction.commit()
    }

    /// The cat sitting where `lane` puts it, its eyes shutting slowly now and then and nothing else moving: what Reduce Motion asks for.
    func showResting(lane: WalkLane) {
        guard isNeeded(on: lane) else {
            stopShowing()
            return
        }
        let metrics = metrics
        let strip = CatSheets.shared.restingStrip()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        prepare(strip: strip, lane: lane, metrics: metrics)
        sprite.removeAllAnimations()
        sprite.add(Self.restingBlink(strip: strip), forKey: Self.framesKey)
        sprite.position = CGPoint(x: aligned(lane.restingX - windowFrame.minX, metrics), y: SpriteMetrics.floor)
        CATransaction.commit()
    }

    /// Takes the cat and every animation away: what a view does when it has nobody to show the cat to.
    func stopShowing() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.removeAllAnimations()
        sprite.isHidden = true
        CATransaction.commit()
    }

    /// A wing the cat can never be seen in (the left one, while the cat keeps to the right) has nothing to animate.
    private func isNeeded(on lane: WalkLane) -> Bool {
        guard lane.clipsToWings else { return true }
        let wing = windowFrame
        let reach = lane.minX...(lane.maxX + metrics.size.width)
        return reach.overlaps(wing.minX...wing.maxX)
    }

    private func prepare(strip: PixelStrip, lane: WalkLane, metrics: SpriteMetrics) {
        // A lane that goes across the camera is drawn only where the wings are; one inside a pill, where it is all notch, is not clipped.
        layer?.masksToBounds = lane.clipsToWings
        sprite.isHidden = false
        sprite.contents = strip.image
        sprite.contentsScale = metrics.backingScale
        sprite.contentsRect = strip.contentsRect(of: 0)
        sprite.bounds = CGRect(origin: .zero, size: metrics.size)
    }

    /// On a device pixel, so that the sprite's pixels fall on the display's.
    private func aligned(_ x: CGFloat, _ metrics: SpriteMetrics) -> CGFloat {
        (x * metrics.backingScale).rounded() / metrics.backingScale
    }

    // MARK: Animations

    /// The picture steps from one frame to the next, held, never blended, over and over, from `elapsed` seconds in.
    static func framesAnimation(strip: PixelStrip, duration: TimeInterval, elapsed: TimeInterval, fps: Double) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "contentsRect")
        animation.values = (0..<strip.frameCount).map { NSValue(rect: strip.contentsRect(of: $0)) }
        animation.calculationMode = .discrete
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.timeOffset = elapsed.truncatingRemainder(dividingBy: duration)
        animation.preferredFrameRateRange = CAFrameRateRange(
            minimum: 4, maximum: frameRateCeiling, preferred: Float(min(max(fps, 4), Double(frameRateCeiling)))
        )
        return animation
    }

    /// One slow blink in every `restingBlinkPeriod` seconds: eyes open for all but one of its slots.
    static let restingBlinkSlots = 12
    static let restingBlinkPeriod: TimeInterval = 6

    static func restingBlink(strip: PixelStrip) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "contentsRect")
        animation.values = (0..<restingBlinkSlots).map { NSValue(rect: strip.contentsRect(of: $0 == restingBlinkSlots - 1 ? 1 : 0)) }
        animation.calculationMode = .discrete
        animation.duration = restingBlinkPeriod
        animation.repeatCount = .infinity
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 1, maximum: 4, preferred: 2)
        return animation
    }

    /// The walk, one sprite pixel at a time: the cat's left foot is at a whole number of sprite pixels from where it started, held, so
    /// that it moves the way a pixel cat does and the render server has nothing to do between steps.
    static func walkAnimation(from: CGFloat, to: CGFloat, step: CGFloat, duration: TimeInterval, elapsed: TimeInterval) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "position.x")
        animation.values = walkStops(from: from, to: to, step: step).map { NSNumber(value: Double($0)) }
        animation.calculationMode = .discrete
        animation.duration = duration
        animation.timeOffset = min(max(elapsed, 0), duration)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        let stepsPerSecond = Double(animation.values?.count ?? 1) / max(duration, 0.001)
        animation.preferredFrameRateRange = CAFrameRateRange(
            minimum: 4, maximum: frameRateCeiling, preferred: Float(min(max(stepsPerSecond, 4), Double(frameRateCeiling)))
        )
        return animation
    }

    /// Every place the cat's foot is held at on its way from `from` towards `to`, `step` apart; the last is as near to `to` as a whole
    /// number of steps gets.
    static func walkStops(from: CGFloat, to: CGFloat, step: CGFloat) -> [CGFloat] {
        guard step > 0, from != to else { return [from] }
        let count = max(Int((abs(to - from) / step).rounded()), 1)
        let direction: CGFloat = to > from ? 1 : -1
        return (0...count).map { from + direction * step * CGFloat($0) }
    }

    static func lastValue(of animation: CAKeyframeAnimation) -> CGFloat {
        CGFloat((animation.values?.last as? NSNumber)?.doubleValue ?? 0)
    }
}

/// The cat in one wing of the collapsed notch. The view is in the tree only while the notch can be seen: a notch that is hidden
/// (fullscreen, a locked screen, a display asleep) takes it out, and with it the animations and everything that ran for them.
struct CatWingView: View {
    let stage: CatStage
    let role: CatSpriteView.Role
    @Environment(\.notchIsOnScreen) private var isOnScreen

    var body: some View {
        if isOnScreen {
            CatSprite(stage: stage, role: role)
        } else {
            Color.clear
        }
    }
}

struct CatSprite: NSViewRepresentable {
    /// What a wing is when the notch does not say: the collapsed notch's side width and a MacBook's notch height.
    static let defaultSize = CGSize(width: 64, height: 32)

    let stage: CatStage
    let role: CatSpriteView.Role

    func makeNSView(context: Context) -> CatSpriteView {
        CatSpriteView(stage: stage, role: role)
    }

    /// Nothing to update: the cat is driven by its stage, not by SwiftUI.
    func updateNSView(_ view: CatSpriteView, context: Context) {}

    /// The wing it is offered, and no size of its own, so the cat never asks the notch to change.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: CatSpriteView, context: Context) -> CGSize? {
        Self.size(for: proposal)
    }

    static func size(for proposal: ProposedViewSize) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: defaultSize)
    }
}
