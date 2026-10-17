import AppKit
import Testing
@testable import PetModule

/// The pointer in the menu bar's row, where the cat lives beside the camera: it is there all the time on its way to something, so the cat
/// is startled by it less: a shorter reach, a pointer that has to stop, and a longer time between two startles.
@Suite(.serialized) @MainActor struct CatBandTests {
    // MARK: What the pointer reads as

    let strip = CGRect(x: 690, y: 1131, width: 100, height: 38)

    @Test func inTheMenuBarsRowNearIsTwentyPointsAndInAStripUnderTheNotchItIsFortyAsItWas() {
        #expect(PointerLook.nearMargin == 40 && PointerLook.bandNearMargin == 20)
        let field = CatField.wings(side: .left, own: CGSize(width: 100, height: 38), partner: CGSize(width: 100, height: 38))
        func near(_ distance: CGFloat, margin: CGFloat) -> Bool? {
            PointerLook.reading(
                of: CGPoint(x: strip.midX, y: strip.minY - distance), strip: strip, lane: field.lane, spriteWidth: field.spriteWidth,
                origin: field.origin, nearMargin: margin
            )?.isNear
        }
        #expect(near(19, margin: PointerLook.bandNearMargin) == true)
        #expect(near(21, margin: PointerLook.bandNearMargin) == false, "seen, not near")
        #expect(near(39, margin: PointerLook.nearMargin) == true)
        #expect(near(21, margin: PointerLook.nearMargin) == true, "near in a strip, as it was")
    }

    @Test func aPointerOverTheRightViewIsAtTheShareOfTheWholeLineThatPlaceIsAndNotOfTheViewAlone() throws {
        let left = CatField.wings(side: .left, own: CGSize(width: 100, height: 38), partner: CGSize(width: 100, height: 38))
        let right = CatField.wings(side: .right, own: CGSize(width: 100, height: 38), partner: CGSize(width: 100, height: 38))
        let rightView = CGRect(x: 1010, y: 1131, width: 100, height: 38)
        // The pointer 50 points into the right view: the cat's middle is at 150 on the line.
        let reading = try #require(PointerLook.reading(
            of: CGPoint(x: rightView.minX + 50, y: rightView.midY), strip: rightView, lane: right.lane, spriteWidth: 32, origin: right.origin
        ))
        #expect(abs(right.lane.x(at: reading.share) + 16 - 150) < 1e-6)
        // And the same pointer read from the left view, were it on that view's own coordinates, is the same share of the same line.
        let leftView = CGRect(x: 690, y: 1131, width: 100, height: 38)
        let seenFromLeft = try #require(PointerLook.reading(
            of: CGPoint(x: leftView.minX + 150, y: leftView.midY), strip: leftView, lane: left.lane, spriteWidth: 32, origin: left.origin
        ))
        #expect(abs(seenFromLeft.share - reading.share) < 1e-9)
    }

    // MARK: Stopping

    @Test func aPointerIsAtRestNearTheCatOnlyOnceItHasNotMovedForAWhile() {
        #expect(PointerDwell.hold == 0.75 && PointerDwell.restWithin == 8)
        var dwell = PointerDwell()
        func settled(near: Bool, at point: CGPoint, now: Double) -> Bool { dwell.isSettled(near: near, at: point, now: now) }
        let spot = CGPoint(x: 700, y: 1150)
        #expect(!settled(near: true, at: spot, now: 0), "it has just come")
        #expect(!settled(near: true, at: spot, now: 0.25))
        #expect(!settled(near: true, at: spot, now: 0.5))
        #expect(settled(near: true, at: spot, now: 0.75), "three quarters of a second at rest")
        #expect(settled(near: true, at: CGPoint(x: spot.x + 5, y: spot.y), now: 1), "a few points is still at rest")
        #expect(!settled(near: true, at: CGPoint(x: spot.x + 40, y: spot.y), now: 1.25), "moving again: it starts over")
        #expect(!settled(near: true, at: CGPoint(x: spot.x + 40, y: spot.y), now: 1.5))
        #expect(!settled(near: false, at: spot, now: 1.75), "away is never settled")
        #expect(!settled(near: true, at: spot, now: 2), "and coming back starts over")
        dwell.reset()
        #expect(!settled(near: true, at: spot, now: 3))
    }

    @Test func aPointerThatIsOnlyPassingThroughTheRowNeverMakesTheCatPounceOrJumpAndOneThatStopsDoes() throws {
        let rig = BodyRig(geometry: Screens.hardware, seed: 4)
        rig.show()
        let host = try #require(rig.hosts.first)
        let wing = try #require(host.screenFrame)
        func reactions() -> Int { rig.stage.presentations }
        func reacted(_ move: CatMove?) -> Bool { move == .pounce || move == .startled }
        // The pointer crosses the left view from end to end in a second, six times in a minute.
        var passes = 0
        for tick in 0..<(4 * 60) {
            let into = (tick % 40) % 8
            rig.pointer.point = tick % 40 < 8
                ? CGPoint(x: wing.minX - 10 + CGFloat(into) * 20, y: wing.midY) : CGPoint(x: 5000, y: 5000)
            rig.advance(0.25)
            if reacted(rig.stage.plan?.move) { passes += 1 }
        }
        #expect(passes == 0, "a pointer on its way somewhere is not a reason to pounce (\(passes) ticks)")
        _ = reactions()
        // Then it stops, over the view.
        rig.pointer.point = CGPoint(x: wing.midX, y: wing.midY)
        var reactedAt: Double?
        for tick in 0..<16 {
            rig.advance(0.25)
            if reacted(rig.stage.plan?.move), reactedAt == nil { reactedAt = Double(tick + 1) * 0.25 }
        }
        let after = try #require(reactedAt, "a pointer that has stopped near it is a reason")
        #expect(after >= PointerDwell.hold - 0.25, "not before it has been still for a while: \(after)")
    }

    @Test func theCatIsStartledOrPouncesAtMostOnceInTwentySecondsInTheRowAndTheOldCooldownStandsInAStrip() throws {
        func reactionCount(_ rig: BodyRig, host: CatSpriteView, seconds: Double) -> Int {
            var count = 0
            var was = false
            let wing = host.screenFrame ?? .zero
            for tick in 0..<Int(seconds * 4) {
                // The pointer comes to the view and stops for two seconds, and goes away for two, over and over.
                rig.pointer.point = (tick / 8) % 2 == 0 ? CGPoint(x: wing.midX, y: wing.midY) : CGPoint(x: 5000, y: 5000)
                rig.advance(0.25)
                let move = rig.stage.plan?.move
                let now = move == .pounce || move == .startled
                if now, !was { count += 1 }
                was = now
            }
            return count
        }
        let rig = BodyRig(geometry: Screens.hardware, seed: 4)
        rig.show()
        let host = try #require(rig.hosts.first)
        let seconds = 100.0
        let band = reactionCount(rig, host: host, seconds: seconds)
        #expect(CatStage.bandReactionCooldown >= 20)
        #expect(band >= 3, "it does react: \(band)")
        #expect(Double(band) <= seconds / CatStage.bandReactionCooldown + 1, "no more often than every \(CatStage.bandReactionCooldown) s: \(band) in \(seconds)")
    }
}
