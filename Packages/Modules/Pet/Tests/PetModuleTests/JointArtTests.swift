import Foundation
import Testing
@testable import PetModule

/// The pictures the scenes with the capybara are made of that the species do not have by themselves: the capybara sunk in its tub to its eyes,
/// and the smaller frog that sits on its head, hops on to it and hops off.
@Suite struct JointArtTests {
    /// Where the ink of a picture is (leaving out what is ignored), as rows and columns of it.
    func ink(_ frame: PixelFrame, ignoring: Set<Character> = ["R"]) -> (top: Int, bottom: Int, left: Int, right: Int)? {
        var found: (top: Int, bottom: Int, left: Int, right: Int)?
        for y in 0..<frame.height {
            for x in 0..<frame.width where frame[x, y] != PixelPalette.clear && !ignoring.contains(frame[x, y]) {
                found = (min(found?.top ?? y, y), max(found?.bottom ?? y, y), min(found?.left ?? x, x), max(found?.right ?? x, x))
            }
        }
        return found
    }

    func letters(_ frame: PixelFrame, in row: Int) -> [Character] { (0..<frame.width).map { frame[$0, row] } }

    let sit = CapybaraArt.animation(for: .soak).frames
    let sink = CapybaraArt.animation(for: .soakSink).frames
    let deep = CapybaraArt.animation(for: .soakDeep).frames
    let rise = CapybaraArt.animation(for: .soakRise).frames
    let tub = CapybaraProps.rippling.frames
    let headSit = FrogArt.animation(for: .headSit).frames
    let headBlink = FrogArt.animation(for: .headBlink).frames
    let hopOn = FrogArt.animation(for: .headHopOn).frames
    let hopOff = FrogArt.animation(for: .headHopOff).frames

    // MARK: The capybara sunk to its eyes

    @Test func itSinksARowAtATimeUntilOnlyTheTopOfItsHeadIsAboveTheWaterAndRisesTheSameWayBack() throws {
        let top = { (frame: PixelFrame) in ink(frame, ignoring: [])?.top ?? -1 }
        let start = top(sit[0])
        #expect(sink.count == 4 && deep.count == 4 && rise.count == 4)
        #expect(sink.indices.map { top(sink[$0]) } == [1, 2, 3, 4].map { start + $0 }, "a row lower each picture: \(sink.indices.map { top(sink[$0]) })")
        for frame in deep { #expect(top(frame) == start + CapybaraArt.deepest, "deep: \(top(frame))") }
        #expect(rise == Array(sink.reversed()), "up the way it came down")
        // And the picture before it and after it is the one that goes on: the last of the sinking is a row from the deep and the first of the
        // rising is, so that nothing jumps.
        #expect(top(deep[0]) - top(sink[3]) == 1 && top(rise[0]) - top(sit[0]) == 4)
    }

    @Test func atItsDeepestItsEyesAreTheRowJustAboveTheWaterAndItsCrownIsWhereTheFrogSitsAndItsBodyIsUnderTheTub() throws {
        let water = CapybaraProps.waterLine
        for (index, frame) in deep.enumerated() {
            let eyes = (0..<frame.height).filter { y in letters(frame, in: y).contains("E") }
            if index == 3 {
                #expect(eyes.isEmpty, "shut, in the blink")
            } else {
                #expect(eyes == [water], "the eyes are the row above the water: \(eyes)")
            }
            // The crown of its head, the line where something sits on it, is a row of dark.
            let crown = CapybaraArt.crown + CapybaraArt.deepest + 1
            #expect(letters(frame, in: crown).filter { $0 == "K" }.count >= 4, "\(index): \(String(letters(frame, in: crown)))")
            // The tub is drawn over it and hides all of it that is below the water, which is all but the head: nothing of it sticks out under or
            // beside it but what does when it soaks as it always did (the rump's line, a few pixels at the foot of the tub's slanting side).
            func outside(_ capybara: PixelFrame, _ cover: PixelFrame) -> Int {
                var count = 0
                for y in (water + 1)..<capybara.height {
                    for x in 0..<capybara.width where capybara[x, y] != PixelPalette.clear && capybara[x, y] != "R" && cover[x, y] == PixelPalette.clear { count += 1 }
                }
                return count
            }
            #expect(outside(frame, tub[index]) <= outside(sit[0], tub[0]) + 4, "deep \(index): \(outside(frame, tub[index])) pixels outside, \(outside(sit[0], tub[0])) when it soaks")
        }
        // It is the same capybara: the same pixels as sitting, a few rows down.
        let shifted = sit[0]
        #expect(ink(shifted, ignoring: [])!.right == ink(deep[0], ignoring: [])!.right, "no wider, no narrower")
    }

    @Test func theMovesTheBrainCountsOnAreWhatTheArtMakesAndTheSinkingAndRisingPlayOnceAndTheDeepGoesRound() {
        for move in [CapybaraMove.soakSink, .soakDeep, .soakRise] {
            let animation = CapybaraArt.animation(for: move)
            #expect(animation.frames.count == move.frameCount && animation.fps == move.fps && animation.loops == move.loops, "\(move)")
            #expect(move.stance == .soaking)
        }
        #expect(!CapybaraMove.soakSink.loops && !CapybaraMove.soakRise.loops && CapybaraMove.soakDeep.loops)
        // The head is what it gives to sit on when it is deep, the back when it sits or soaks, and nothing in between.
        #expect(CapybaraMove.soakDeep.perchSpot == .head && CapybaraMove.soak.perchSpot == .back && CapybaraMove.sit.perchSpot == .back)
        #expect(CapybaraMove.soakSink.perchSpot == nil && CapybaraMove.soakRise.perchSpot == nil && CapybaraMove.doze.perchSpot == nil)
    }

    // MARK: The smaller frog

    @Test func theFrogOnTheHeadIsAFrogOfNineRowsThatFitsOverTheCrownAndIsNotCutOffAtTheTop() throws {
        for (index, frame) in (headSit + headBlink).enumerated() {
            let box = try #require(ink(frame))
            #expect(box.bottom - box.top + 1 <= 10 && box.bottom - box.top + 1 >= 7, "\(index): \(box.bottom - box.top + 1) rows")
            #expect(box.right - box.left + 1 <= 16, "\(index): \(box.right - box.left + 1) across")
            // Whole: the row above the line round it is the rim and nothing else, and the picture is not cut off by the top.
            #expect(box.top >= 1, "\(index): the line round it is on the picture")
            #expect(letters(frame, in: 0).allSatisfy { $0 == "." || $0 == "R" })
            // Green with a pale belly, and a gold eye while it is open: a frog.
            #expect(frame.cells.contains("G") && frame.cells.contains("W"), "\(index)")
            if index < headSit.count { #expect(frame.cells.contains("Y"), "\(index): the eye") }
        }
    }

    @Test func itSitsOnTheCrownOfTheCapybarasHeadTouchingItAndNotFloatingOrSunkIntoItAndOverTheHeadAndNotTheBody() throws {
        let head = try #require(ink(deep[0]))
        for (index, frame) in headSit.enumerated() {
            let box = try #require(ink(frame))
            // Its feet are on the row of the capybara's ears (the top of its head): they touch it, or overlap it by a row.
            #expect(box.bottom >= head.top - 2 && box.bottom <= head.top + 1, "\(index): feet at \(box.bottom), the head's top at \(head.top)")
            // Over the head, which is towards the front: the middle of it is over the head's columns.
            let middle = (box.left + box.right) / 2
            #expect((17...27).contains(middle), "\(index): over column \(middle)")
        }
    }

    @Test func itBlinksItsEyesAndBreathesTheSittingPicturesDifferAndTheBlinkShutsThem() {
        #expect(Set(headSit.map(\.cells)).count >= 2, "it breathes")
        let open = headSit[0].cells.filter { $0 == "Y" }.count
        #expect(open >= 3)
        let shut = headBlink[1].cells.filter { $0 == "Y" }.count
        #expect(shut < open, "the blink shuts the eye: \(shut) of gold against \(open)")
    }

    @Test func theHopOnIsTheUsualFrogGoingUpAndShrinkingToTheSmallOneOnTheCrown() throws {
        #expect(hopOn.count == 6)
        let boxes = try hopOn.map { try #require(ink($0)) }
        // The crouch and the push are the frog of its usual size, on the ground.
        let usual = try #require(ink(FrogArt.animation(for: .sit).frames[0]))
        #expect(boxes[0].bottom == usual.bottom && boxes[0].bottom - boxes[0].top >= 8)
        #expect(boxes[1].bottom - boxes[1].top >= 10)
        // Then up it goes, to the place it sits: each picture is higher than the last, and smaller, and the last is the one it sits in.
        for index in 2..<6 { #expect(boxes[index].bottom < boxes[index - 1].bottom + 1, "\(index): rising: \(boxes.map(\.bottom))") }
        for index in 3..<6 { #expect(boxes[index].bottom - boxes[index].top <= boxes[index - 1].bottom - boxes[index - 1].top + 1, "\(index): shrinking") }
        let seat = try #require(ink(headSit[0]))
        #expect(abs(boxes[5].bottom - seat.bottom) <= 1 && abs((boxes[5].left + boxes[5].right) / 2 - (seat.left + seat.right) / 2) <= 2, "it lands where it sits: \(boxes[5]) and \(seat)")
        // Nothing of it is above the picture.
        for (index, box) in boxes.enumerated() { #expect(box.top >= 1, "\(index): cut off at the top") }
    }

    @Test func theHopOffIsTheSmallFrogLeavingTheCrownAndGrowingToTheUsualOneOnTheGroundAndItIsDrawnForTheOtherWay() throws {
        #expect(hopOff.count == 6)
        let boxes = try hopOff.map { try #require(ink($0)) }
        // It begins on the crown of the head of a capybara that faces the other way: the middle of the head is the mirror of where it is for the
        // one it hopped on to.
        let seat = try #require(ink(headSit[0]))
        let mirrored = 31 - (seat.left + seat.right) / 2
        #expect(abs((boxes[0].left + boxes[0].right) / 2 - mirrored) <= 3, "starts over the head: \(boxes[0]) for \(mirrored)")
        #expect(abs(boxes[0].bottom - seat.bottom) <= 1)
        // It ends on the ground, the usual size.
        let usual = try #require(ink(FrogArt.animation(for: .sit).frames[0]))
        #expect(boxes[5].bottom == usual.bottom && boxes[5].bottom - boxes[5].top >= 8, "\(boxes[5])")
        for index in 3..<6 { #expect(boxes[index].bottom >= boxes[index - 1].bottom, "\(index): falling: \(boxes.map(\.bottom))") }
        for (index, box) in boxes.enumerated() { #expect(box.top >= 1, "\(index): cut off at the top") }
    }

    @Test func theViewsStripsAreMadeForBothWaysAndMirrorTheOtherWayForTheFrogAndTheCapybara() {
        for move in [FrogMove.headHopOn, .headSit, .headBlink, .headHopOff] {
            let right = FrogSheets.shared.strip(for: move, facing: .right)
            let left = FrogSheets.shared.strip(for: move, facing: .left)
            #expect(right.frameCount == move.frameCount && left.frameCount == move.frameCount, "\(move)")
        }
        for move in [CapybaraMove.soakSink, .soakDeep, .soakRise] {
            #expect(CapybaraSheets.shared.strip(for: move, facing: .right).frameCount == move.frameCount, "\(move)")
        }
        // The pose says which: the frog on the head is over the capybara and a frog on the ground is not.
        #expect(FrogMove.headSit.isOnTheHead && FrogMove.headHopOn.isOnTheHead && FrogMove.headHopOff.isOnTheHead && !FrogMove.hop.isOnTheHead)
        #expect(FrogMove.headSit.stance == .head && FrogMove.headHopOn.stance == .head && FrogMove.headHopOff.stance == .ground)
    }
}
