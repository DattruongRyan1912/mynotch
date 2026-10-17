import AppKit
import NotchUI
import SwiftUI

/// A lane the characters play in, as a view: the strip under the notch, the body of a virtual notch, or one side of a hardware notch's
/// camera. It owns three layers for each character (`CharacterLayers`: its picture, what it plays with and its portal), in the order the
/// stage draws them in, and hands everything that moves to Core Animation. A character's frames are one keyframe animation of the layer's
/// `contentsRect` along a strip of pictures, its walk is another of its position, and nothing is redrawn or laid out by SwiftUI while
/// either runs. The view takes them all away the moment it leaves its window.
///
/// A character is drawn at one pixel of its picture to the point, which is two device pixels on a Retina display and three on a bigger
/// scale, with nearest-neighbour filtering, so it is sharp on all of them.
final class CatSpriteView: NSView {
    /// What the view is: the strip under the notch (today's), one view across the body of a virtual notch, or one of the two views of a
    /// hardware notch's top row, left and right of the camera.
    enum Role: Equatable {
        case strip, lane, leftWing, rightWing

        var isStrip: Bool { self == .strip }
    }

    /// How far in front of the others a character is that sits on one of them.
    static let raisedHeight: CGFloat = 1
    static let framesKey = "catFrames"
    static let walkKey = "catWalk"
    static let bobKey = "propBob"
    static let portalKey = "catPortal"
    /// The frame rate the render server is asked to hold the cat's animations to, whatever the display can do.
    static let frameRateCeiling: Float = 24
    /// Between the cat's feet and the bottom of the strip, in points.
    static let floor = CatField.stripFloor
    /// A head that peeks comes up from below the edge: the bottom of its picture, which is the rim, is below the strip's own bottom and is
    /// cut off by it, so that nothing is left of the head's cut but the head.
    static let peekSink: CGFloat = 2
    /// What the cat's picture measures, in points.
    static let spriteSize = CGSize(width: CatArt.width, height: CatArt.height)
    /// How high a moth flutters, from the bottom of the strip, and how far it bobs.
    static let mothHeight: CGFloat = CatField.stripFloor + CGFloat(PropArt.mothRise)
    static let mothBob: [CGFloat] = [0, 3, 5, 4, 1, -1, 2, 4, 3, 0]

    /// The stage that shows this view, which is its display's: set by the registry, nil while the display has no characters. A view that
    /// is handed a stage (a test's, with no registry) keeps it.
    weak var stage: CatStage?
    /// The registry that puts this view on the stage of the display it is in; nil for a view made for one stage.
    private(set) weak var home: CatStages?
    let role: Role
    /// The view on the other side of the camera, for a view that is one of two.
    weak var partner: CatSpriteView?
    /// What each character on the stage is drawn with, in the order they are drawn in: there is always one, for the first.
    private(set) var characters: [CharacterLayers]

    /// The first character's layers, which is the cat's when there is only the cat: the picture, what it plays with, and its portal.
    var sprite: CALayer { characters[0].sprite }
    var prop: CALayer { characters[0].prop }
    var portal: CALayer { characters[0].portal }

    /// The layers of the first character can be handed in, which is what a test does to see in what order they are told things.
    init(stage: CatStage, role: Role = .strip, sprite: CALayer = CALayer(), prop: CALayer = CALayer()) {
        self.stage = stage
        self.role = role
        characters = [CharacterLayers(sprite: sprite, prop: prop)]
        super.init(frame: .zero)
        configureLayers()
    }

    /// A view that is shown by the stage of the display it is in, whichever that is.
    init(stages: CatStages, role: Role = .strip) {
        home = stages
        self.role = role
        characters = [CharacterLayers()]
        super.init(frame: .zero)
        configureLayers()
    }

    private func configureLayers() {
        wantsLayer = true
        layer?.masksToBounds = true
        characters[0].all.forEach { layer?.addSublayer($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Geometry

    /// Whether the view that holds this one in the top row of a notch has its wings laid out for a camera that is not where it is now, or
    /// this one is shown by the stage of a display it has left.
    var isInStaleLayout: Bool {
        if let container = superview as? CatBodyContainer { return container.isStale }
        return home?.isRoutedElsewhere(self) ?? false
    }

    /// Asks for the view that holds this one to be laid out again, or this one if none does: it is laid out only when AppKit has a reason
    /// to, which a window that moved is not.
    func askForLayout() {
        if let container = superview as? CatBodyContainer { container.needsLayout = true } else { needsLayout = true }
    }

    /// The strip's frame on the screen; nil outside a window.
    var screenFrame: CGRect? { window.map { $0.convertToScreen(convert(bounds, to: nil)) } }

    /// The strip's frame in its window's coordinates, which is how a change of place is noticed.
    var windowFrame: CGRect { convert(bounds, to: nil) }

    /// Where the cat plays, and how this view lies in it.
    var field: CatField {
        switch role {
        case .strip: .strip(width: bounds.width)
        case .lane: .lane(width: bounds.width, height: bounds.height)
        case .leftWing: .wings(side: .left, own: bounds.size, partner: partner?.bounds.size)
        case .rightWing: .wings(side: .right, own: bounds.size, partner: partner?.bounds.size)
        }
    }

    /// Where the cat can walk, along the field's line (in this view's coordinates when it is the one view there is).
    var lane: WalkLane { field.lane }

    /// Whether anything is animating on the layers.
    var isAnimating: Bool { characters.contains { $0.isAnimating } }

    /// Whether the cat is drawn: false when it has been taken away.
    var isShowingCat: Bool { !sprite.isHidden }

    var isShowingProp: Bool { !prop.isHidden }

    override func layout() {
        super.layout()
        home?.reroute(self)
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
        switch (window, home) {
        case (nil, let home?): home.detach(self)
        case (nil, nil): stage?.detach(self)
        case (_?, let home?): home.attach(self)
        case (_?, nil): stage?.attach(self)
        }
    }

    // MARK: Clicks

    /// Only the cat takes clicks, so the rest of the strip opens the notch as it always did. It is hit where the cat is drawn at this
    /// moment, which on a walk is not where the layer's value says.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local), drawnCharacter(at: local) != nil else { return nil }
        return self
    }

    /// The character drawn at `point` (in this view's coordinates), the topmost when several are: its number on the stage. One that sits on
    /// another is drawn over it, whatever its number, and so is the one that is hit.
    private func drawnCharacter(at point: CGPoint) -> Int? {
        let topmost = characters.indices.sorted { (characters[$0].sprite.zPosition, $0) > (characters[$1].sprite.zPosition, $1) }
        return topmost.first { index in
            let sprite = characters[index].sprite
            guard !sprite.isHidden else { return false }
            let drawn = sprite.presentation() ?? sprite
            guard drawn.frame.insetBy(dx: -2, dy: -2).contains(point) else { return false }
            // One that sits on another is hit only where it is drawn: its picture is the size of the other's, and its clear corners would
            // otherwise take the strokes that are for the one under it.
            return sprite.zPosition > 0 ? Self.hasInk(drawn, near: point) : true
        }
    }

    /// Whether the picture a layer shows has a pixel that is not clear within a pixel of `point` (in the view's coordinates).
    private static func hasInk(_ layer: CALayer, near point: CGPoint) -> Bool {
        guard let contents = layer.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID else { return true }
        let image = contents as! CGImage
        let (frame, rect) = (layer.frame, layer.contentsRect)
        guard frame.width > 0, frame.height > 0 else { return false }
        // The point in the picture: left to right as the layer is, and up from the foot as a layer is (rows of the image go down).
        let across = rect.minX + (point.x - frame.minX) / frame.width * rect.width
        let up = rect.minY + (point.y - frame.minY) / frame.height * rect.height
        let (column, row) = (Int((across * CGFloat(image.width)).rounded(.down)), Int(((1 - up) * CGFloat(image.height)).rounded(.down)))
        let area = CGRect(x: column - 1, y: row - 1, width: 3, height: 3).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !area.isNull, let piece = image.cropping(to: area) else { return false }
        var pixels = [UInt8](repeating: 0, count: piece.width * piece.height * 4)
        guard let context = CGContext(
            data: &pixels, width: piece.width, height: piece.height, bitsPerComponent: 8, bytesPerRow: piece.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(piece, in: CGRect(x: 0, y: 0, width: piece.width, height: piece.height))
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 }
    }

    /// The panel never becomes active, so the first click has to be taken for what it is.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }

    /// A click on the cat is a stroke, and goes no further: it does not reach the notch's own tap, which would open it. It is for the one
    /// that was clicked, and for the first when none is where the click is.
    override func mouseDown(with event: NSEvent) {
        stage?.catWasClicked(character: drawnCharacter(at: convert(event.locationInWindow, from: nil)) ?? 0)
    }

    // MARK: Showing

    /// How far the place a leg ended may be from where the next plan says it begins for the plan to go on from where the leg ended: a leg of
    /// a walk ends on a whole step, up to half a step from where the share of the lane rounds to.
    static let continuityLimit: CGFloat = 4

    /// Where a leg that begins at `place` really begins: where the last leg ended, if that is the same place within half a step (so that one
    /// leg begins exactly where the last one ended, and the cat never jumps a few points), and `place` if the cat is elsewhere (a leg that was
    /// cut short) or was not shown.
    static func continued(from current: CGFloat?, near place: CGFloat, scale: Int = 1) -> CGFloat {
        guard let current, abs(current - place) <= continuityLimit * CGFloat(scale) else { return place }
        return current
    }

    /// Plays `plan` along the lane from `elapsed` seconds into it, in the coat given: the cat alone.
    func show(plan: CatPlan, elapsed: TimeInterval, coat: CatCoat, at mediaTime: CFTimeInterval = CACurrentMediaTime()) {
        show(
            characters: [CharacterDrawing(species: CatSpecies.shared, pose: plan.pose, elapsed: elapsed, appearance: Appearance(coat: coat))],
            at: mediaTime
        )
    }

    /// Plays every character's pose along the lane, each on layers of its own, in the order given: the first at the bottom. All of them are
    /// shown the one moment, `mediaTime`, which is what keeps the two views of a notch's top row in step.
    func show(characters drawings: [CharacterDrawing], at mediaTime: CFTimeInterval = CACurrentMediaTime()) {
        fit(to: drawings)
        for (drawing, layers) in zip(drawings, characters) { show(drawing, on: layers, at: mediaTime) }
    }

    /// One set of layers for each character, whom they are for the same each time so that none is drawn over by another's picture: a
    /// character that is not who the layers had is begun again on them.
    private func fit(to drawings: [CharacterDrawing]) {
        fit(to: drawings.map(\.species))
    }

    private func fit(to species: [any Species]) {
        let wanted = max(species.count, 1)
        if characters.count != wanted {
            characters.dropFirst(wanted).forEach { layers in
                layers.stopShowing()
                layers.all.forEach { $0.removeFromSuperlayer() }
            }
            characters = Array(characters.prefix(wanted))
            while characters.count < wanted { characters.append(CharacterLayers()) }
            // The order of the layers is the order of the characters.
            for layers in characters where layers.sprite.superlayer !== layer { layers.all.forEach { layer?.addSublayer($0) } }
        }
        for (one, layers) in zip(species, characters) where layers.species != ObjectIdentifier(one) {
            if layers.species != nil { layers.stopShowing() }
            layers.species = ObjectIdentifier(one)
        }
        characters.dropFirst(species.count).forEach { $0.stopShowing() }
    }

    /// Plays one pose.
    ///
    /// **The layer itself is where the character stands, never where it is going.** A leg is an animation of the layer's position, and until
    /// the render server is drawing that animation the layer's own value is what is on the screen. So the layer is set to where the leg
    /// begins, together with the animation that takes it away, and is moved to where the leg ends only when the animation says it is over
    /// (`LegEnd`); the animation, which holds its last place (`.forwards`) and its first until it begins (`.backwards`), shows the rest.
    ///
    /// When a leg takes the place of another, in the one transaction: the layer is set to where the new leg begins, and only then is the
    /// old animation taken away, so that the layer never shows a place it has been left at by the old leg (where that began), and then the
    /// new animations go on. Nothing here waits for the old leg to say it is over.
    private func show(_ drawing: CharacterDrawing, on layers: CharacterLayers, at mediaTime: CFTimeInterval) {
        let (pose, elapsed) = (drawing.pose, drawing.elapsed)
        let (sprite, portal) = (layers.sprite, layers.portal)
        let field = field
        let scale = CGFloat(field.scale)
        let strip = drawing.species.strip(for: pose.motion, facing: pose.facing, appearance: drawing.appearance)
        let rate = max(pose.fpsScale, 0.1)
        let effectiveFPS = pose.motion.fps * rate
        let sameField = layers.shownField == field
        layers.shownField = field
        let from = Self.continued(
            from: sprite.isHidden || !sameField ? nil : layers.spriteStands, near: field.local(share: pose.from), scale: field.scale
        )
        // A character that stays where it is stays where it is, on whatever whole step the last leg ended.
        let to = pose.to == pose.from ? from : field.local(share: pose.to)
        let floor = field.baseY(height: bounds.height, isStrip: role.isStrip)
        // A head that peeks comes up from below the edge: the strip's, or the bottom of the notch's body.
        let base = pose.motion.sinks ? (role.isStrip ? floor : 0) - Self.peekSink * scale : floor
        let begin = sprite.convertTime(mediaTime, from: nil)
        layers.spriteLeg += 1
        let leg = layers.spriteLeg
        var walk: CAKeyframeAnimation?
        if from != to {
            let moving = max(pose.duration * (1 - pose.delay), 0.05)
            let step = max((abs(to - from) / (moving * effectiveFPS)).rounded(), 1)
            let animation = Self.walkAnimation(
                from: from, to: to, step: step, duration: pose.duration, delay: pose.delay, elapsed: elapsed, begin: begin, rate: effectiveFPS
            )
            let ends = Self.lastValue(of: animation)
            animation.delegate = LegEnd { [weak self, weak layers] in
                guard let layers else { return }
                self?.arrived(at: ends, leg: leg, onTheCat: true, in: layers)
            }
            walk = animation
        }
        layers.spriteStands = walk.map(Self.lastValue(of:)) ?? from
        let frames = Self.framesAnimation(strip: strip, fps: effectiveFPS, loops: pose.motion.loops, elapsed: elapsed, begin: begin)
        let size = CGSize(width: Self.spriteSize.width * scale, height: Self.spriteSize.height * scale)
        let portals = walk.flatMap { portalAnimation(for: $0, field: field, begin: begin, elapsed: elapsed) }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // One that sits on another is over it: it is drawn above every character that does not, with what it plays with.
        sprite.zPosition = pose.raised ? Self.raisedHeight : 0
        layers.prop.zPosition = sprite.zPosition
        prepare(sprite, strip: strip, size: size)
        sprite.position = CGPoint(x: from, y: base)
        sprite.removeAllAnimations()
        sprite.add(frames, forKey: Self.framesKey)
        if let walk { sprite.add(walk, forKey: Self.walkKey) }
        showPortal(portals, on: portal, field: field, y: floor)
        showProp(of: drawing, on: layers, field: field, floor: floor, sameField: sameField, begin: begin)
        CATransaction.commit()
    }

    /// What the character plays with: a moth that flutters along a path of its own, or a ball of yarn that lies or rolls. Like the
    /// character, it is where it begins until its path says it is going, and it is set there before its old animations go.
    private func showProp(
        of drawing: CharacterDrawing, on layers: CharacterLayers, field: CatField, floor: CGFloat, sameField: Bool, begin: CFTimeInterval
    ) {
        let (pose, elapsed, prop) = (drawing.pose, drawing.elapsed, layers.prop)
        let current = prop.isHidden || !sameField ? nil : layers.propStands
        layers.propLeg += 1
        guard let item = pose.prop else {
            prop.removeAllAnimations()
            prop.isHidden = true
            layers.propStands = nil
            return
        }
        let leg = layers.propLeg
        let scale = CGFloat(field.scale)
        let strip = drawing.species.propStrip(item.look)
        let size = CGSize(width: CGFloat(strip.frameWidth) * scale, height: CGFloat(strip.frameHeight) * scale)
        let from = Self.continued(from: current, near: field.local(unbounded: item.from), scale: field.scale)
        let to = item.to == item.from ? from : field.local(unbounded: item.to)
        // A moth flutters as high above the character's feet as it does in the strip.
        let height = floor + CGFloat(item.look.rise) * scale
        var path: CAKeyframeAnimation?
        if from != to {
            let step = max((abs(to - from) / (pose.duration * 12)).rounded(), 1)
            let animation = Self.walkAnimation(
                from: from, to: to, step: step, duration: pose.duration, delay: 0, elapsed: elapsed, begin: begin, rate: 12
            )
            let ends = Self.lastValue(of: animation)
            animation.delegate = LegEnd { [weak self, weak layers] in
                guard let layers else { return }
                self?.arrived(at: ends, leg: leg, onTheCat: false, in: layers)
            }
            path = animation
        }
        layers.propStands = path.map(Self.lastValue(of:)) ?? from
        prepare(prop, strip: strip, size: size)
        prop.position = CGPoint(x: from, y: height)
        prop.removeAllAnimations()
        // What does not move is still while it lies (a ball of yarn); what flies goes on with its wings (a moth).
        guard item.look.animatesInPlace || path != nil else { return }
        prop.add(
            Self.framesAnimation(strip: strip, fps: item.look.fps, loops: item.look.loops, elapsed: elapsed, begin: begin), forKey: Self.framesKey
        )
        if let path { prop.add(path, forKey: Self.walkKey) }
        if item.look.flutters {
            prop.add(Self.bobAnimation(base: height, elapsed: elapsed, begin: begin, scale: scale), forKey: Self.bobKey)
        }
    }

    // MARK: Portals

    /// How long a portal takes to open before the cat is at it, and to close after the cat is through, in seconds, and how fast its swirl
    /// turns.
    static let portalLead: TimeInterval = 0.2
    static let portalLag: TimeInterval = 0.2
    static let portalFPS = 10.0

    /// The portal's frames from the start of a leg: nothing until a little before the cat reaches the crossing, then the portal opening,
    /// swirling for as long as the cat is in the crossing, and closing, and nothing again. Played from `contentsRect` of the portal's strip
    /// (frame 0 is clear), begun when the leg began, so the portal is on the layer as clear as it is after, and never shows before its time.
    /// Nil for a leg that does not go through the crossing.
    private func portalAnimation(
        for walk: CAKeyframeAnimation, field: CatField, begin: CFTimeInterval, elapsed: TimeInterval
    ) -> CAKeyframeAnimation? {
        guard let crossing = field.crossing, role == .leftWing || role == .rightWing,
              let places = walk.values as? [NSNumber], places.count > 1 else { return nil }
        // Where the cat's foot is at each stop of the walk, along the field's line, and the slot of the walk it is shown in.
        let stops = places.map { CGFloat($0.doubleValue) + field.origin }
        let slot = walk.duration / Double(stops.count)
        guard let first = stops.first, let last = stops.last, first != last else { return nil }
        let rising = last > first
        // Only a leg that goes through the crossing, from before it or from inside it, to after it, has a portal.
        guard rising ? (first < crossing.upperBound && last >= crossing.upperBound) : (first > crossing.lowerBound && last <= crossing.lowerBound),
              let inside = stops.firstIndex(where: { rising ? $0 >= crossing.lowerBound : $0 <= crossing.upperBound }),
              let outside = stops.firstIndex(where: { rising ? $0 >= crossing.upperBound : $0 <= crossing.lowerBound }) else { return nil }
        let opens = max(Double(inside) * slot - Self.portalLead, 0)
        let closes = Double(outside) * slot + Self.portalLag
        let period = 1 / Self.portalFPS
        func count(_ seconds: Double) -> Int { max(Int((seconds / period).rounded()), 1) }
        // A leg that begins at the crossing has the portal open from its first moment: the animation begins when the leg does, never before.
        let waiting = Int((opens / period).rounded())
        let strip = CatSheets.shared.portalStrip()
        func rect(_ picture: Int) -> NSValue { NSValue(rect: strip.contentsRect(of: picture)) }
        // Clear until it opens, opening, swirling while the cat goes through, closing, clear.
        var sequence = Array(repeating: rect(PortalArt.clear), count: waiting)
        sequence += [rect(PortalArt.opening), rect(PortalArt.opening)]
        for index in 0..<max(count(closes - opens - Self.portalLead - Self.portalLag), 2) {
            sequence.append(rect(index % 2 == 0 ? PortalArt.swirlA : PortalArt.swirlB))
        }
        sequence += [rect(PortalArt.opening), rect(PortalArt.opening), rect(PortalArt.clear)]
        let animation = CAKeyframeAnimation(keyPath: "contentsRect")
        animation.values = sequence
        animation.calculationMode = .discrete
        animation.duration = Double(sequence.count) * period
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 4, maximum: Self.frameRateCeiling, preferred: Float(Self.portalFPS))
        Self.started(animation, at: begin, elapsed: min(max(elapsed, 0), walk.duration))
        return animation
    }

    /// Sets the portal at the inner edge of this view, clear, with the animation that opens it (nil: none, and it stays clear).
    private func showPortal(_ animation: CAKeyframeAnimation?, on portal: CALayer, field: CatField, y: CGFloat) {
        portal.removeAllAnimations()
        guard role == .leftWing || role == .rightWing else {
            portal.isHidden = true
            return
        }
        let strip = CatSheets.shared.portalStrip()
        portal.isHidden = false
        portal.contents = strip.image
        portal.contentsScale = window?.backingScaleFactor ?? 2
        portal.contentsRect = strip.contentsRect(of: PortalArt.clear)
        portal.bounds = CGRect(origin: .zero, size: field.portalSize)
        portal.position = CGPoint(x: role == .leftWing ? bounds.width - field.portalSize.width : 0, y: y)
        if let animation { portal.add(animation, forKey: Self.portalKey) }
    }

    /// The cat's leg (or the prop's) is over, and the animation is holding its last place: the layer is moved there too, so that whatever
    /// shows the layer without the animation shows where the cat stands, and the next leg begins there. A leg that has been replaced by
    /// another is not the one to say so.
    func arrived(at x: CGFloat, leg: Int, onTheCat: Bool, in layers: CharacterLayers? = nil) {
        let layers = layers ?? characters[0]
        let layer = onTheCat ? layers.sprite : layers.prop
        guard leg == (onTheCat ? layers.spriteLeg : layers.propLeg), !layer.isHidden else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = CGPoint(x: x, y: layer.position.y)
        CATransaction.commit()
    }

    /// Tells a view when an animation of its position is over, which the animation's delegate does when it ran to its end.
    private final class LegEnd: NSObject, CAAnimationDelegate {
        private let handler: @MainActor () -> Void

        init(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }

        nonisolated func animationDidStop(_ animation: CAAnimation, finished: Bool) {
            guard finished else { return }
            MainActor.assumeIsolated { handler() }
        }
    }

    /// The cat sitting in the middle of the strip, its eyes shutting slowly now and then and nothing else moving: what Reduce Motion asks for.
    func showResting(coat: CatCoat) {
        showResting([CatSpecies.shared], appearance: Appearance(coat: coat))
    }

    /// Every character sitting still, at a place of its own, its eyes shutting now and then: what Reduce Motion asks for.
    func showResting(_ species: [any Species], appearance: Appearance) {
        guard !species.isEmpty else {
            stopShowing()
            return
        }
        fit(to: species)
        let field = field
        let places = field.restingPlaces(count: species.count)
        let size = CGSize(width: Self.spriteSize.width * CGFloat(field.scale), height: Self.spriteSize.height * CGFloat(field.scale))
        for (index, one) in species.enumerated() {
            let layers = characters[index]
            let strip = one.restingStrip(appearance: appearance)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layers.spriteLeg += 1
            layers.propLeg += 1
            layers.spriteStands = nil
            layers.propStands = nil
            layers.shownField = nil
            layers.sprite.zPosition = 0
            layers.prop.zPosition = 0
            prepare(layers.sprite, strip: strip, size: size)
            layers.sprite.position = CGPoint(
                x: field.local(places[index].rounded()), y: field.baseY(height: bounds.height, isStrip: role.isStrip)
            )
            layers.sprite.removeAllAnimations()
            layers.sprite.add(Self.restingBlink(strip: strip), forKey: Self.framesKey)
            layers.prop.removeAllAnimations()
            layers.prop.isHidden = true
            layers.portal.removeAllAnimations()
            layers.portal.isHidden = true
            CATransaction.commit()
        }
    }

    /// Takes every character and every animation away: what a view does when it has nobody to show.
    func stopShowing() {
        characters.forEach { $0.stopShowing() }
    }

    private func prepare(_ layer: CALayer, strip: PixelStrip, size: CGSize) {
        layer.isHidden = false
        layer.contents = strip.image
        layer.contentsScale = window?.backingScaleFactor ?? 2
        layer.contentsRect = strip.contentsRect(of: 0)
        layer.bounds = CGRect(origin: .zero, size: size)
    }

    // MARK: Animations

    /// Where on its timeline an animation that is `elapsed` seconds in begins: it begins at `begin`, which is now, less that. **Never with
    /// `timeOffset`**, which does not skip the first part of an animation but moves it to the end: the timeline wraps round, so that an
    /// animation held when it is over (`.forwards`) is held on what it showed at the offset, which is its first frame and not its last,
    /// and for the `elapsed` seconds before its end it plays its first part once more.
    private static func started(_ animation: CAKeyframeAnimation, at begin: CFTimeInterval, elapsed: TimeInterval) {
        animation.beginTime = begin - elapsed
    }

    /// The picture steps from one frame to the next, held, never blended: round and round, or once and then held on the last frame. It
    /// began `elapsed` seconds before `begin`.
    static func framesAnimation(
        strip: PixelStrip, fps: Double, loops: Bool, elapsed: TimeInterval, begin: CFTimeInterval
    ) -> CAKeyframeAnimation {
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
            started(animation, at: begin, elapsed: elapsed.truncatingRemainder(dividingBy: animation.duration))
        } else {
            animation.isRemovedOnCompletion = false
            started(animation, at: begin, elapsed: min(max(elapsed, 0), animation.duration))
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
        from: CGFloat, to: CGFloat, step: CGFloat, duration: TimeInterval, delay: Double, elapsed: TimeInterval, begin: CFTimeInterval,
        rate: Double
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
        started(animation, at: begin, elapsed: min(max(elapsed, 0), duration))
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
    static func bobAnimation(base: CGFloat, elapsed: TimeInterval, begin: CFTimeInterval, scale: CGFloat = 1) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: "position.y")
        animation.values = mothBob.map { NSNumber(value: Double(base + $0 * scale)) }
        animation.calculationMode = .discrete
        animation.duration = Double(mothBob.count) / 10
        animation.repeatCount = .infinity
        animation.fillMode = .both
        started(animation, at: begin, elapsed: elapsed.truncatingRemainder(dividingBy: animation.duration))
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
    let stages: CatStages
    @Environment(\.notchIsOnScreen) private var isOnScreen

    var body: some View {
        if isOnScreen {
            CatSprite(stages: stages)
        } else {
            Color.clear
        }
    }
}

struct CatSprite: NSViewRepresentable {
    /// How tall the strip is, and how wide when the notch does not say.
    static let defaultSize = CGSize(width: 300, height: CatActivity.stripHeight)

    let stages: CatStages

    func makeNSView(context: Context) -> CatSpriteView {
        CatSpriteView(stages: stages)
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
