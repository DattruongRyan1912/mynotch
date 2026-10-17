import AppKit
import NotchUI
import SwiftUI

/// The strip under the notch, as a view: it owns two layers, one with the cat's picture on it and one with what it plays with, and hands
/// everything that moves to Core Animation. The cat's frames are one keyframe animation of the layer's `contentsRect` along a strip of
/// pictures, its walk is another of its position, and nothing is redrawn or laid out by SwiftUI while either runs. The view takes both
/// away the moment it leaves its window.
///
/// The cat is drawn at one pixel of its picture to the point, which is two device pixels on a Retina display and three on a bigger
/// scale, with nearest-neighbour filtering, so it is sharp on all of them.
final class CatSpriteView: NSView {
    static let framesKey = "catFrames"
    static let walkKey = "catWalk"
    static let bobKey = "propBob"
    /// The frame rate the render server is asked to hold the cat's animations to, whatever the display can do.
    static let frameRateCeiling: Float = 24
    /// Between the cat's feet and the bottom of the strip, in points.
    static let floor: CGFloat = 1
    /// A head that peeks comes up from below the edge: the bottom of its picture, which is the rim, is below the strip's own bottom and is
    /// cut off by it, so that nothing is left of the head's cut but the head.
    static let peekSink: CGFloat = 2
    /// What the cat's picture measures, in points.
    static let spriteSize = CGSize(width: CatArt.width, height: CatArt.height)
    /// How high a moth flutters, from the bottom of the strip, and how far it bobs.
    static let mothHeight: CGFloat = 12
    static let mothBob: [CGFloat] = [0, 3, 5, 4, 1, -1, 2, 4, 3, 0]

    private(set) weak var stage: CatStage?
    /// The cat. Anchored at its bottom left corner, so its position is the place of its left foot.
    let sprite = CALayer()
    /// The moth or the ball of yarn.
    let prop = CALayer()

    init(stage: CatStage) {
        self.stage = stage
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        for layer in [sprite, prop] {
            layer.anchorPoint = .zero
            layer.contentsGravity = .resize
            // Nearest neighbour both ways: any other filter smears the pixels.
            layer.magnificationFilter = .nearest
            layer.minificationFilter = .nearest
            layer.isHidden = true
            self.layer?.addSublayer(layer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Geometry

    /// The strip's frame on the screen; nil outside a window.
    var screenFrame: CGRect? { window.map { $0.convertToScreen(convert(bounds, to: nil)) } }

    /// The strip's frame in its window's coordinates, which is how a change of place is noticed.
    var windowFrame: CGRect { convert(bounds, to: nil) }

    /// Where the cat can walk, in this view's coordinates.
    var lane: WalkLane { WalkLane(width: bounds.width, spriteWidth: Self.spriteSize.width) }

    /// Whether anything is animating on the layers.
    var isAnimating: Bool { !(sprite.animationKeys() ?? []).isEmpty || !(prop.animationKeys() ?? []).isEmpty }

    /// Whether the cat is drawn: false when it has been taken away.
    var isShowingCat: Bool { !sprite.isHidden }

    var isShowingProp: Bool { !prop.isHidden }

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

    /// Only the cat takes clicks, so the rest of the strip opens the notch as it always did. It is hit where the cat is drawn at this
    /// moment, which on a walk is not where the layer's value says.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !sprite.isHidden, let superview else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        let drawn = (sprite.presentation() ?? sprite).frame.insetBy(dx: -2, dy: -2)
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

    /// How far the model's place may be from where a plan says it begins for the plan to go on from the model's: a leg of a walk ends on a
    /// whole step, a few points from where the share of the lane rounds to.
    static let continuityLimit: CGFloat = 8

    /// Where a leg that begins at `place` really begins: where the layer already is, if that is the same place within a step (so that one
    /// leg begins exactly where the last one ended, and the cat never jumps a few points), and `place` if the layer is elsewhere or not shown.
    static func continued(from current: CGFloat?, near place: CGFloat) -> CGFloat {
        guard let current, abs(current - place) <= continuityLimit else { return place }
        return current
    }

    /// Plays `plan` along the lane from `elapsed` seconds into it, in the coat given.
    ///
    /// What the layer holds when nothing animates it is set first, and is where the leg ends; every animation holds its own first value
    /// from the moment it is added (`.both`), because the render server may draw the first frame from a moment that is before the
    /// animation's begin time, and that frame shows the layer's own value: which, for a leg back across the strip, is the other end of it.
    func show(plan: CatPlan, elapsed: TimeInterval, coat: CatCoat) {
        let lane = lane
        let strip = CatSheets.shared.strip(for: plan.move, facing: plan.facing, coat: coat)
        let rate = max(plan.fpsScale, 0.1)
        let effectiveFPS = plan.move.fps * rate
        let from = Self.continued(from: sprite.isHidden ? nil : sprite.position.x, near: lane.x(at: plan.from).rounded())
        // A cat that stays where it is stays where it is, on whatever whole step the last leg ended.
        let to = plan.to == plan.from ? from : lane.x(at: plan.to).rounded()
        let base = plan.move == .peek ? Self.floor - Self.peekSink : Self.floor
        var walk: CAKeyframeAnimation?
        if from != to {
            let moving = max(plan.duration * (1 - plan.delay), 0.05)
            let step = max((abs(to - from) / (moving * effectiveFPS)).rounded(), 1)
            walk = Self.walkAnimation(
                from: from, to: to, step: step, duration: plan.duration, delay: plan.delay, elapsed: elapsed, rate: effectiveFPS
            )
        }
        let frames = Self.framesAnimation(strip: strip, fps: effectiveFPS, loops: plan.move.loops, elapsed: elapsed)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        prepare(sprite, strip: strip, size: Self.spriteSize)
        sprite.removeAllAnimations()
        sprite.position = CGPoint(x: walk.map(Self.lastValue(of:)) ?? from, y: base)
        sprite.add(frames, forKey: Self.framesKey)
        if let walk { sprite.add(walk, forKey: Self.walkKey) }
        showProp(of: plan, lane: lane, elapsed: elapsed)
        CATransaction.commit()
    }

    /// What the cat plays with: a moth that flutters along a path of its own, or a ball of yarn that lies or rolls.
    private func showProp(of plan: CatPlan, lane: WalkLane, elapsed: TimeInterval) {
        let current = prop.isHidden ? nil : prop.position.x
        prop.removeAllAnimations()
        guard let item = plan.prop else {
            prop.isHidden = true
            return
        }
        let strip = CatSheets.shared.propStrip(item.kind)
        let size = CGSize(width: strip.frameWidth, height: strip.frameHeight)
        prepare(prop, strip: strip, size: size)
        let from = Self.continued(from: current, near: lane.unboundedX(at: item.from).rounded())
        let to = item.to == item.from ? from : lane.unboundedX(at: item.to).rounded()
        let height = item.kind == .moth ? Self.mothHeight : Self.floor
        var path: CAKeyframeAnimation?
        if from != to {
            let step = max((abs(to - from) / (plan.duration * 12)).rounded(), 1)
            path = Self.walkAnimation(from: from, to: to, step: step, duration: plan.duration, delay: 0, elapsed: elapsed, rate: 12)
        }
        // Where it stops is where the next plan of the scene finds it.
        prop.position = CGPoint(x: path.map(Self.lastValue(of:)) ?? from, y: height)
        switch item.kind {
        case .moth:
            prop.add(Self.framesAnimation(strip: strip, fps: PropArt.moth.fps, loops: true, elapsed: elapsed), forKey: Self.framesKey)
            if let path { prop.add(path, forKey: Self.walkKey) }
            prop.add(Self.bobAnimation(base: height, elapsed: elapsed), forKey: Self.bobKey)
        case .yarn:
            guard let path else { return }
            prop.add(Self.framesAnimation(strip: strip, fps: PropArt.yarn.fps, loops: true, elapsed: elapsed), forKey: Self.framesKey)
            prop.add(path, forKey: Self.walkKey)
        }
    }

    /// The cat sitting in the middle of the strip, its eyes shutting slowly now and then and nothing else moving: what Reduce Motion asks for.
    func showResting(coat: CatCoat) {
        let lane = lane
        let strip = CatSheets.shared.restingStrip(coat: coat)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        prepare(sprite, strip: strip, size: Self.spriteSize)
        sprite.removeAllAnimations()
        sprite.add(Self.restingBlink(strip: strip), forKey: Self.framesKey)
        sprite.position = CGPoint(x: lane.restingX.rounded(), y: Self.floor)
        prop.removeAllAnimations()
        prop.isHidden = true
        CATransaction.commit()
    }

    /// Takes the cat and every animation away: what a view does when it has nobody to show the cat to.
    func stopShowing() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.removeAllAnimations()
        prop.removeAllAnimations()
        sprite.isHidden = true
        prop.isHidden = true
        CATransaction.commit()
    }

    private func prepare(_ layer: CALayer, strip: PixelStrip, size: CGSize) {
        layer.isHidden = false
        layer.contents = strip.image
        layer.contentsScale = window?.backingScaleFactor ?? 2
        layer.contentsRect = strip.contentsRect(of: 0)
        layer.bounds = CGRect(origin: .zero, size: size)
    }

    // MARK: Animations

    /// The picture steps from one frame to the next, held, never blended: round and round, or once and then held on the last frame. It
    /// begins `elapsed` seconds in.
    static func framesAnimation(strip: PixelStrip, fps: Double, loops: Bool, elapsed: TimeInterval) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "contentsRect")
        animation.values = (0..<strip.frameCount).map { NSValue(rect: strip.contentsRect(of: $0)) }
        animation.calculationMode = .discrete
        animation.duration = Double(strip.frameCount) / fps
        animation.preferredFrameRateRange = CAFrameRateRange(
            minimum: 4, maximum: frameRateCeiling, preferred: Float(min(max(fps, 4), Double(frameRateCeiling)))
        )
        // Held on its first frame until it begins, and on its last when it is over.
        animation.fillMode = .both
        if loops {
            animation.repeatCount = .infinity
            animation.timeOffset = elapsed.truncatingRemainder(dividingBy: animation.duration)
        } else {
            animation.isRemovedOnCompletion = false
            animation.timeOffset = min(max(elapsed, 0), animation.duration)
        }
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

    /// The walk, a few points at a time: the cat's left foot is at a whole number of `step`s from where it started, held, so that it moves
    /// the way a pixel cat does and the render server has nothing to do between steps. For the first `delay` of the plan it stays where it
    /// is.
    static func walkAnimation(
        from: CGFloat, to: CGFloat, step: CGFloat, duration: TimeInterval, delay: Double, elapsed: TimeInterval, rate: Double
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "position.x")
        var places = walkStops(from: from, to: to, step: step)
        if delay > 0 {
            let held = max(Int((Double(places.count) * delay / (1 - delay)).rounded()), 1)
            places = Array(repeating: from, count: held) + places
        }
        animation.values = places.map { NSNumber(value: Double($0)) }
        animation.calculationMode = .discrete
        animation.duration = duration
        animation.timeOffset = min(max(elapsed, 0), duration)
        // Held on its first place until it begins, and on its last when it is over.
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        animation.preferredFrameRateRange = CAFrameRateRange(
            minimum: 4, maximum: frameRateCeiling, preferred: Float(min(max(rate, 4), Double(frameRateCeiling)))
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

    /// A moth does not fly straight: it bobs, round and round, ten times a second.
    static func bobAnimation(base: CGFloat, elapsed: TimeInterval) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "position.y")
        animation.values = mothBob.map { NSNumber(value: Double(base + $0)) }
        animation.calculationMode = .discrete
        animation.duration = Double(mothBob.count) / 10
        animation.repeatCount = .infinity
        animation.fillMode = .both
        animation.timeOffset = elapsed.truncatingRemainder(dividingBy: animation.duration)
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 4, maximum: frameRateCeiling, preferred: 10)
        return animation
    }

    static func lastValue(of animation: CAKeyframeAnimation) -> CGFloat {
        CGFloat((animation.values?.last as? NSNumber)?.doubleValue ?? 0)
    }
}

/// The cat on the strip under the collapsed notch. The view is in the tree only while the notch can be seen: a notch that is hidden
/// (fullscreen, a locked screen, a display asleep) takes it out, and with it the animations and everything that ran for them.
struct CatStripView: View {
    let stage: CatStage
    @Environment(\.notchIsOnScreen) private var isOnScreen

    var body: some View {
        if isOnScreen {
            CatSprite(stage: stage)
        } else {
            Color.clear
        }
    }
}

struct CatSprite: NSViewRepresentable {
    /// How tall the strip is, and how wide when the notch does not say.
    static let defaultSize = CGSize(width: 300, height: CatActivity.stripHeight)

    let stage: CatStage

    func makeNSView(context: Context) -> CatSpriteView {
        CatSpriteView(stage: stage)
    }

    /// Nothing to update: the cat is driven by its stage, not by SwiftUI.
    func updateNSView(_ view: CatSpriteView, context: Context) {}

    /// The strip it is offered, and no size of its own, so the cat never asks the notch to change.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: CatSpriteView, context: Context) -> CGSize? {
        Self.size(for: proposal)
    }

    static func size(for proposal: ProposedViewSize) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: defaultSize)
    }
}
