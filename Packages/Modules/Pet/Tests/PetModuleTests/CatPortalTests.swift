import AppKit
import Metal
import QuartzCore
import Testing
@testable import PetModule

/// The cat in the top row of the notch through half an hour, on a hardware notch (two views, a portal at each edge of the camera) and on a
/// virtual one (one lane): where it stops, what it does, and when the portals are open.
@Suite(.serialized) @MainActor struct CatPortalTests {
    /// The cat's place along the field's line at `time` seconds into a walk, from its stops (a stop is shown for its slot).
    func place(of walk: CAKeyframeAnimation, at time: Double, origin: CGFloat) -> CGFloat {
        let stops = (walk.values as? [NSNumber] ?? []).map { CGFloat($0.doubleValue) + origin }
        let slot = walk.duration / Double(stops.count)
        return stops[min(max(Int(time / slot), 0), stops.count - 1)]
    }

    /// Which picture the portal shows at `time` seconds from the start of its animation: 0 is clear.
    func portalPicture(_ animation: CAKeyframeAnimation, at time: Double) -> Int {
        let strip = CatSheets.shared.portalStrip()
        let rects = (animation.values as? [NSValue] ?? []).map(\.rectValue)
        let index = min(max(Int(time / (animation.duration / Double(rects.count))), 0), rects.count - 1)
        return (0..<strip.frameCount).first { strip.contentsRect(of: $0) == rects[index] } ?? -1
    }

    // MARK: Where the cat stops

    /// Half an hour on a hardware notch: the plans it makes, and the places it is shown at when it is not going anywhere.
    @Test func onAHardwareNotchTheCatNeverStopsInTheCrossingOrPartInOneViewAndPartInTheOtherThroughHalfAnHour() throws {
        for seed: UInt64 in [3, 8] {
            let rig = BodyRig(geometry: Screens.hardware, seed: seed)
            rig.show()
            let left = try #require(rig.container.leftWing)
            let right = try #require(rig.container.rightWing)
            let field = left.field
            let crossing = try #require(field.crossing)
            var seen = Set<CatScene>()
            var through = 0
            var stationary = 0
            var last: CatPlan?
            let portalWidth = CGFloat(CatField.portalWidth)
            for tick in 0..<(4 * 60 * 30) {
                if tick % 480 == 200 { rig.pointer.point = CGPoint(x: 1150, y: 1165) } else if tick % 480 == 230 { rig.pointer.point = CGPoint(x: 5000, y: 5000) }
                rig.advance(0.25)
                if let scene = rig.stage.scene { seen.insert(scene) }
                guard let plan = rig.stage.plan, plan != last else { continue }
                last = plan
                let (from, to) = (field.lane.x(at: plan.from), field.lane.x(at: plan.to))
                #expect(!crossing.contains(to) || to == crossing.lowerBound || to == crossing.upperBound, "seed \(seed): a \(plan.move) ends at \(to)")
                let goesThrough = (from <= crossing.lowerBound && to >= crossing.upperBound) || (from >= crossing.upperBound && to <= crossing.lowerBound)
                if goesThrough { through += 1 }
                if plan.from == plan.to {
                    stationary += 1
                    // Whole in one view and clear of its portal: exactly one of the two views has the cat in it, and not under a portal.
                    let visible = [left, right].filter { host in
                        let frame = CGRect(origin: host.sprite.position, size: host.sprite.bounds.size)
                        return frame.intersects(host.bounds)
                    }
                    #expect(visible.count == 1, "seed \(seed): a \(plan.move) with the cat in \(visible.count) of the views")
                    if let host = visible.first, plan.prop == nil || plan.move != .peek {
                        let x = host.sprite.position.x
                        let clear = host === left ? x + 32 <= host.bounds.width - portalWidth : x >= portalWidth
                        #expect(clear, "seed \(seed): a \(plan.move) with the cat at \(x) of \(host.bounds.width), under the portal")
                    }
                }
            }
            #expect(through >= 3, "seed \(seed): it goes through the portal now and then: \(through) times")
            #expect(stationary > 200)
            #expect(seen.count >= 8, "seed \(seed): \(seen.count) scenes: \(seen)")
        }
    }

    @Test func onAVirtualNotchTheCatIsInsideTheBodyThroughHalfAnHourAndPlaysAsManyScenes() throws {
        for geometry in [Screens.pill, Screens.notch, Screens.tallPill] {
            let rig = BodyRig(geometry: geometry, seed: 5)
            rig.show()
            let lane = try #require(rig.container.lane)
            var seen = Set<CatScene>()
            var places = Set<Int>()
            for _ in 0..<(4 * 60 * 30) {
                rig.advance(0.25)
                if let scene = rig.stage.scene { seen.insert(scene) }
                var xs = [lane.sprite.position.x]
                if let walk = lane.sprite.animation(forKey: CatSpriteView.walkKey) as? CAKeyframeAnimation {
                    xs += (walk.values as? [NSNumber] ?? []).map { CGFloat($0.doubleValue) }
                }
                let width = lane.sprite.bounds.width
                for x in xs { #expect(x >= 0 && x + width <= lane.bounds.width, "the cat at \(x) in \(lane.bounds.width) (\(geometry.kind))") }
                places.insert(Int(lane.sprite.position.x / 20))
            }
            #expect(places.count > 5, "it covers the body")
            #expect(seen.count >= 8, "\(seen.count) scenes: \(seen)")
        }
    }

    @Test func withTheStripChosenOnAHardwareNotchNoViewOfTheBodyHasTheCat() throws {
        let rig = BodyRig(geometry: Screens.hardware, place: .strip)
        // The body's view for it is not in the tree (see `CatBodyView`); the container, made all the same, would build the wings.
        rig.show()
        #expect(rig.stage.isAlive)
        rig.hide()
        #expect(!rig.stage.isAlive)
    }

    // MARK: The portals

    /// The legs of the cat that go through the portal and the ones that do not, with what each of the two views does for them.
    func legs(seed: UInt64, minutes: Int, _ body: (CatPlan, CatSpriteView, CatSpriteView) throws -> Void) throws {
        let rig = BodyRig(geometry: Screens.hardware, seed: seed)
        rig.show()
        let left = try #require(rig.container.leftWing)
        let right = try #require(rig.container.rightWing)
        var last: CatPlan?
        for _ in 0..<(4 * 60 * minutes) {
            rig.advance(0.25)
            guard let plan = rig.stage.plan, plan != last else { continue }
            last = plan
            try body(plan, left, right)
        }
    }

    @Test func aLegThroughTheCrossingOpensAPortalAtTheEdgeOfEachViewAndAnyOtherLegHasNone() throws {
        var through = 0
        var elsewhere = 0
        try legs(seed: 3, minutes: 30) { plan, left, right in
            let field = left.field
            let crossing = try #require(field.crossing)
            let (from, to) = (field.lane.x(at: plan.from), field.lane.x(at: plan.to))
            let goesThrough = from <= crossing.lowerBound && to >= crossing.upperBound || from >= crossing.upperBound && to <= crossing.lowerBound
            for host in [left, right] {
                let animation = host.portal.animation(forKey: CatSpriteView.portalKey) as? CAKeyframeAnimation
                #expect((animation != nil) == goesThrough, "\(plan.move) from \(from) to \(to): a portal \(animation != nil)")
                // The portal is clear when it is not open, whatever else: the model is the clear picture.
                let strip = CatSheets.shared.portalStrip()
                #expect(host.portal.contentsRect == strip.contentsRect(of: PortalArt.clear))
            }
            if goesThrough { through += 1 } else { elsewhere += 1 }
        }
        #expect(through >= 3 && elsewhere > 50)
    }

    @Test func thePortalsAreClearBeforeTheyOpenAndAfterTheyCloseAndOpenWhileTheCatIsInTheCrossingOnBothViewsTogether() throws {
        var checked = 0
        try legs(seed: 3, minutes: 40) { plan, left, right in
            let field = left.field
            let crossing = try #require(field.crossing)
            guard let walk = left.sprite.animation(forKey: CatSpriteView.walkKey) as? CAKeyframeAnimation,
                  let one = left.portal.animation(forKey: CatSpriteView.portalKey) as? CAKeyframeAnimation,
                  let two = right.portal.animation(forKey: CatSpriteView.portalKey) as? CAKeyframeAnimation else { return }
            checked += 1
            // Never a time offset (which wraps an animation round), and begun as the leg is.
            #expect(one.timeOffset == 0 && two.timeOffset == 0)
            let otherWalk = try #require(right.sprite.animation(forKey: CatSpriteView.walkKey) as? CAKeyframeAnimation)
            #expect(abs(one.beginTime - walk.beginTime) < 1e-9 && abs(two.beginTime - otherWalk.beginTime) < 1e-9, "each begun as its own view's leg is")
            #expect(abs(one.beginTime - two.beginTime) < 0.005, "and the two together")
            #expect(one.fillMode == .both && !one.isRemovedOnCompletion, "held on its last picture, which is clear")
            // Clear until it opens, unless the cat begins its leg at the crossing: then it is open from the first moment of the leg.
            let startsAt = place(of: walk, at: 0, origin: left.field.origin)
            let startRising = place(of: walk, at: walk.duration, origin: left.field.origin) > startsAt
            let startApproach = startRising ? crossing.lowerBound - startsAt : startsAt - crossing.upperBound
            let startPace = [CatMove.walk, .trot, .chase, .frantic, .pounce].contains(plan.move) ? plan.move.speed : 24
            if startApproach > startPace * 0.3 { #expect(portalPicture(one, at: 0) == PortalArt.clear, "clear until it opens: the cat is \(startApproach) points away") }
            #expect(portalPicture(one, at: one.duration + 5) == PortalArt.clear, "and clear when it is over")
            let origin = left.field.origin
            var time = 0.0
            while time < walk.duration {
                let cat = place(of: walk, at: time, origin: origin)
                let picture = portalPicture(one, at: time)
                #expect(picture == portalPicture(two, at: time), "both portals are the same picture")
                if crossing.contains(cat) {
                    #expect(picture != PortalArt.clear, "the cat is at \(cat) in the crossing and the portal is shut at \(time) of \(walk.duration)")
                }
                // Just before it: open already, even for a leg that begins there.
                let rising = place(of: walk, at: walk.duration, origin: origin) > place(of: walk, at: 0, origin: origin)
                let approaching = rising ? crossing.lowerBound - cat : cat - crossing.upperBound
                let pace = [CatMove.walk, .trot, .chase, .frantic, .pounce].contains(plan.move) ? plan.move.speed : 24
                if approaching > 0, approaching <= pace * 0.1 {
                    #expect(picture != PortalArt.clear, "the cat is \(approaching) points from the crossing and the portal is not open yet at \(time)")
                }
                // Well away from it, a second either side (a cat goes at 24 points a second and more): shut.
                let away = cat < crossing.lowerBound ? crossing.lowerBound - cat : cat > crossing.upperBound ? cat - crossing.upperBound : 0
                let walking = [CatMove.walk, .trot, .chase, .frantic, .pounce].contains(plan.move) ? plan.move.speed : 24
                if away > walking * 0.6 + 16 { #expect(picture == PortalArt.clear, "far from the crossing (\(away) points) and open at \(time)") }
                time += 0.05
            }
            // And after it: still open for a little while after the cat has gone through.
            let stops = (walk.values as? [NSNumber] ?? []).map { CGFloat($0.doubleValue) + origin }
            let slot = walk.duration / Double(stops.count)
            let leftIt = stops.firstIndex { stop in stops[0] < crossing.lowerBound ? stop >= crossing.upperBound : stop <= crossing.lowerBound }
            if let leftIt {
                let at = Double(leftIt) * slot
                #expect(portalPicture(one, at: at + 0.02) != PortalArt.clear, "the cat has just gone through and the portal has shut")
                #expect(portalPicture(one, at: at + 0.1) != PortalArt.clear, "a tenth of a second after")
            }
        }
        #expect(checked >= 3, "the test checked \(checked) crossings")
    }

    // MARK: The portal drawn

    /// The top row of the Mac's notch drawn offscreen with the portal showing `picture` and nothing else: the pixels of each portal's
    /// columns, which are the last ten of the left view and the first ten of the right.
    func rendered(portal picture: Int) throws -> (left: [UInt8], right: [UInt8], all: [UInt8], width: Int, height: Int)? {
        guard MTLCreateSystemDefaultDevice() != nil else { return nil }
        // The two views of the Mac's notch, 100 points each side of a camera of 220, with no window and no screen.
        let stage = CatStage(scheduler: ManualSchedulerStub.make())
        let left = CatSpriteView(stage: stage, role: .leftWing)
        let right = CatSpriteView(stage: stage, role: .rightWing)
        left.partner = right
        right.partner = left
        left.frame = CGRect(x: 0, y: 0, width: 100, height: 38)
        right.frame = CGRect(x: 320, y: 0, width: 100, height: 38)
        let plan = CatPlan(move: .walk, facing: .right, from: 0.2, to: 0.9, began: 0, duration: 9)
        let strip = CatSheets.shared.portalStrip()
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 420, height: 38)
        root.anchorPoint = .zero
        root.backgroundColor = CGColor(gray: 0.1, alpha: 1)
        for host in [left, right] {
            host.show(plan: plan, elapsed: 0, coat: .tabby)
            host.sprite.isHidden = true
            host.prop.isHidden = true
            host.portal.removeAllAnimations()
            host.portal.isHidden = false
            host.portal.contentsRect = strip.contentsRect(of: picture)
            let layer = try #require(host.layer)
            layer.frame = host.frame
            root.addSublayer(layer)
        }
        let offscreen = try #require(CatRenderTests.Offscreen(layer: root, width: 420, height: 38))
        CATransaction.flush()
        let bytes = offscreen.render(atTime: CACurrentMediaTime())
        func columns(_ range: Range<Int>) -> [UInt8] {
            var result: [UInt8] = []
            for y in 0..<38 {
                for x in range {
                    let start = (y * 420 + x) * 4
                    result.append(contentsOf: bytes[start..<(start + 4)])
                }
            }
            return result
        }
        return (columns(90..<100), columns(320..<330), bytes, 420, 38)
    }

    /// How many pixels of `bytes` (BGRA) are `colour` (0xRRGGBB), give or take what a colour-managed layer does to it.
    func count(_ colour: UInt32, in bytes: [UInt8]) -> Int {
        let red = Int((colour >> 16) & 0xFF)
        let green = Int((colour >> 8) & 0xFF)
        let blue = Int(colour & 0xFF)
        var total = 0
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let near = abs(Int(bytes[offset + 2]) - red) <= 12 && abs(Int(bytes[offset + 1]) - green) <= 12 && abs(Int(bytes[offset]) - blue) <= 12
            if near { total += 1 }
        }
        return total
    }

    @Test func eachPictureOfThePortalIsDrawnAtTheInnerEdgeOfBothViewsAndNowhereElse() throws {
        guard let clear = try rendered(portal: PortalArt.clear) else { return }
        let violet: UInt32 = 0x8B5CF6, cyan: UInt32 = 0x22D3EE
        #expect(count(violet, in: clear.all) == 0 && count(cyan, in: clear.all) == 0, "a portal that is not open draws nothing")
        var inks: [Int: Int] = [:]
        var images: [[UInt8]] = []
        for picture in [PortalArt.opening, PortalArt.swirlA, PortalArt.swirlB] {
            let drawn = try #require(try rendered(portal: picture))
            let ink = count(violet, in: drawn.all) + count(cyan, in: drawn.all)
            inks[picture] = ink
            #expect(count(violet, in: drawn.left) > 0 && count(violet, in: drawn.right) > 0, "the ring is at the edge of each view (\(picture))")
            #expect(count(violet, in: drawn.all) == count(violet, in: drawn.left) + count(violet, in: drawn.right), "and nowhere else (\(picture))")
            images.append(drawn.all)
        }
        let (opening, swirl) = (try #require(inks[PortalArt.opening]), try #require(inks[PortalArt.swirlA]))
        #expect(opening < swirl / 2, "it opens: smaller than it swirls (\(opening) and \(swirl))")
        #expect(images[1] != images[2], "the swirl turns from one picture to the next")
        let swirling = try #require(try rendered(portal: PortalArt.swirlA))
        #expect(count(cyan, in: swirling.left) > 0 && count(cyan, in: swirling.right) > 0, "with its swirl inside the ring")
    }

    @Test func thePortalPicturesAreTheSameSizeAsTheCatsAndAllFourAreInOneStrip() {
        #expect(PortalArt.frames.count == 4)
        for frame in PortalArt.frames { #expect(frame.width == CatField.portalWidth && frame.height == 24) }
        #expect(PortalArt.frames[PortalArt.clear].inkCount == 0)
        #expect(Set(PortalArt.frames.map(\.cells)).count == 4, "four different pictures")
        let strip = CatSheets.shared.portalStrip()
        #expect(strip.frameCount == 4 && strip.frameWidth == 10 && strip.frameHeight == 24)
        #expect(CatSheets.shared.portalStrip().image === strip.image, "made once")
        // Every colour of it is in the palette of every coat.
        for coat in CatCoat.allCases { for letter in Set(PortalArt.frames.flatMap(\.cells)) { #expect(coat.palette.isKnown(letter)) } }
    }

    @Test func aCatThatIsPartInEachViewIsDrawnWholeAcrossThemWithNothingLostAndNothingTwice() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        let stage = CatStage(scheduler: ManualSchedulerStub.make())
        let left = CatSpriteView(stage: stage, role: .leftWing)
        let right = CatSpriteView(stage: stage, role: .rightWing)
        left.partner = right
        right.partner = left
        left.frame = CGRect(x: 0, y: 0, width: 100, height: 38)
        right.frame = CGRect(x: 320, y: 0, width: 100, height: 38)
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 420, height: 38)
        root.anchorPoint = .zero
        let ground = CGColor(gray: 0.1, alpha: 1)
        root.backgroundColor = ground
        for host in [left, right] {
            host.show(plan: CatPlan(move: .sit, facing: .right, from: 0.2, to: 0.2, began: 0, duration: 9), elapsed: 0, coat: .tabby)
            host.portal.isHidden = true
            host.sprite.removeAllAnimations()
            let layer = try #require(host.layer)
            layer.frame = host.frame
            root.addSublayer(layer)
        }
        let offscreen = try #require(CatRenderTests.Offscreen(layer: root, width: 420, height: 38))
        let whole = CatArt.animation(for: .sit).frames[0].inkCount
        // The cat's foot at 84 on the line: its first 16 points are in the left view, which ends at 100, and its last 16 in the right.
        for (place, share) in [(84.0, 16.0 / 32), (70.0, 30.0 / 32), (100.0, 0.0), (52.0, 32.0 / 32)] {
            left.sprite.position.x = place
            right.sprite.position.x = place - 100
            CATransaction.flush()
            let bytes = offscreen.render(atTime: CACurrentMediaTime())
            var ink = 0
            for offset in stride(from: 0, to: bytes.count, by: 4) {
                let different = abs(Int(bytes[offset]) - 26) > 8 || abs(Int(bytes[offset + 1]) - 26) > 8 || abs(Int(bytes[offset + 2]) - 26) > 8
                if different { ink += 1 }
            }
            #expect(ink == whole, "the cat at \(place): \(ink) pixels of its \(whole) are drawn (\(Int(share * 100)) % of it in the left view)")
        }
    }

    @Test func theCatInATallPillIsMadeOfBlocksOfTwoByTwoPointsEachOfOneColour() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        let stage = CatStage(scheduler: ManualSchedulerStub.make())
        let lane = CatSpriteView(stage: stage, role: .lane)
        lane.frame = CGRect(x: 0, y: 0, width: 313, height: 56)
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 313, height: 56)
        root.anchorPoint = .zero
        root.backgroundColor = CGColor(gray: 0.1, alpha: 1)
        lane.show(plan: CatPlan(move: .sit, facing: .right, from: 0, to: 0, began: 0, duration: 9), elapsed: 0, coat: .tabby)
        lane.sprite.removeAllAnimations()
        let layer = try #require(lane.layer)
        layer.frame = lane.frame
        root.addSublayer(layer)
        let offscreen = try #require(CatRenderTests.Offscreen(layer: root, width: 313, height: 56))
        CATransaction.flush()
        let bytes = offscreen.render(atTime: CACurrentMediaTime())
        func colour(_ x: Int, _ y: Int) -> [UInt8] { Array(bytes[(y * 313 + x) * 4..<(y * 313 + x) * 4 + 4]) }
        let (left, rows, columns) = (Int(lane.sprite.position.x), 24, 32)
        let bottom = Int(lane.sprite.position.y)
        #expect(lane.sprite.bounds.size == CGSize(width: 64, height: 48) && bottom == 4)
        // Which way up the renderer lays its texture out is its own: both are tried, and one has to be crisp throughout.
        var crisp = [true, true]
        for (index, top) in [56 - bottom - 48, bottom].enumerated() {
            for row in 0..<rows {
                for column in 0..<columns {
                    let block = (0..<2).flatMap { dy in (0..<2).map { dx in colour(left + column * 2 + dx, top + row * 2 + dy) } }
                    if Set(block).count != 1 { crisp[index] = false }
                }
            }
        }
        #expect(crisp.contains(true), "every pixel of the cat is a block of two by two points of one colour")
    }
}
