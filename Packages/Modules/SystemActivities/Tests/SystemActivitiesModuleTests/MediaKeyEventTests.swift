import AppKit
import Testing
@testable import SystemActivitiesModule

/// The `data1` of a system-defined event: key code in the high 16 bits, flags in the low 16 (state in the high byte of
/// those, 0xA down and 0xB up, and bit 0 for an auto-repeat).
private func data1(key: Int, state: Int, isRepeat: Bool = false) -> Int {
    (key << 16) | (state << 8) | (isRepeat ? 1 : 0)
}

@Suite struct MediaKeyEventTests {
    @Test(arguments: [
        (0, MediaKey.volumeUp), (1, .volumeDown), (7, .mute),
        (2, .brightnessUp), (3, .brightnessDown),
        (21, .keyboardLightUp), (22, .keyboardLightDown), (23, .keyboardLightToggle),
    ])
    func decodesEachKeyOfTheAuxControlButtons(code: Int, key: MediaKey) {
        let event = MediaKeyEvent(subtype: 8, data1: data1(key: code, state: 0xA), modifiers: [])
        #expect(event == MediaKeyEvent(key: key, isDown: true, isRepeat: false, isFine: false))
    }

    @Test func tellsKeyDownFromKeyUpAndRepeat() {
        let down = MediaKeyEvent(subtype: 8, data1: data1(key: 0, state: 0xA), modifiers: [])
        let held = MediaKeyEvent(subtype: 8, data1: data1(key: 0, state: 0xA, isRepeat: true), modifiers: [])
        let up = MediaKeyEvent(subtype: 8, data1: data1(key: 0, state: 0xB), modifiers: [])
        #expect(down?.isDown == true && down?.isRepeat == false)
        #expect(held?.isDown == true && held?.isRepeat == true)
        #expect(up?.isDown == false)
    }

    @Test func optionAndShiftTogetherMeanFineSteps() {
        func isFine(_ modifiers: NSEvent.ModifierFlags) -> Bool? {
            MediaKeyEvent(subtype: 8, data1: data1(key: 0, state: 0xA), modifiers: modifiers)?.isFine
        }
        #expect(isFine([.option, .shift]) == true)
        #expect(isFine([.option]) == false)
        #expect(isFine([.shift]) == false)
        #expect(isFine([]) == false)
        #expect(isFine([.capsLock, .function]) == false)
    }

    @Test(arguments: [NSEvent.ModifierFlags.command, .control, [.command, .shift], [.control, .option], [.option, .shift, .command]])
    func aKeyPressedWithCommandOrControlIsNotOursAndPassesUntouched(modifiers: NSEvent.ModifierFlags) {
        // The system gives those combinations their own meaning, e.g. display mirroring.
        #expect(MediaKeyEvent(subtype: 8, data1: data1(key: 0, state: 0xA), modifiers: modifiers) == nil)
        #expect(MediaKeyEvent(subtype: 8, data1: data1(key: 2, state: 0xB), modifiers: modifiers) == nil)
    }

    @Test func theDeviceDependentBitsOfAnEventsFlagsAreNotModifiers() {
        // A system-defined event carries 0xA00 (its key state) in the flags' low bits.
        let flags = NSEvent.ModifierFlags(rawValue: 0xA00)
        #expect(MediaKeyEvent(subtype: 8, data1: data1(key: 0, state: 0xA), modifiers: flags)?.isFine == false)
    }

    @Test func ignoresOtherSubtypes() {
        // Subtype 7 is "mouse" for a system-defined event; 8 is the aux control buttons.
        #expect(MediaKeyEvent(subtype: 7, data1: data1(key: 0, state: 0xA), modifiers: []) == nil)
        #expect(MediaKeyEvent(subtype: 0, data1: data1(key: 0, state: 0xA), modifiers: []) == nil)
    }

    @Test(arguments: [4, 5, 6, 8, 10, 16, 17, 18, 19, 20, 24, 0xFFFF])
    func ignoresKeysThatAreNotOurs(code: Int) {
        // 16 is play/pause, 17 next, 18 previous: the Media module's keys, which must never be touched here.
        #expect(MediaKeyEvent(subtype: 8, data1: data1(key: code, state: 0xA), modifiers: []) == nil)
    }

    @Test(arguments: [0x0, 0x1, 0x9, 0xC, 0xFF])
    func ignoresAStateThatIsNeitherDownNorUp(state: Int) {
        #expect(MediaKeyEvent(subtype: 8, data1: data1(key: 0, state: state), modifiers: []) == nil)
    }

    @Test func eachKeyBelongsToOneTarget() {
        #expect([MediaKey.volumeUp, .volumeDown, .mute].allSatisfy { $0.target == .volume })
        #expect([MediaKey.brightnessUp, .brightnessDown].allSatisfy { $0.target == .brightness })
        #expect([MediaKey.keyboardLightUp, .keyboardLightDown, .keyboardLightToggle].allSatisfy { $0.target == .keyboardLight })
    }
}

@Suite struct LevelStepTests {
    @Test func volumeMovesOneSixteenth() {
        #expect(LevelStep.moved(0, up: true, steps: 16) == 1.0 / 16)
        #expect(LevelStep.moved(0.5, up: true, steps: 16) == 0.5625)
        #expect(LevelStep.moved(0.5, up: false, steps: 16) == 0.4375)
    }

    @Test func fineMovesOneSixtyFourth() {
        #expect(LevelStep.moved(0.5, up: true, steps: 64) == 0.515625)
        #expect(LevelStep.moved(0.5, up: false, steps: 64) == 0.484375)
    }

    @Test func aLevelBetweenGridLinesGoesToTheNextLineInTheDirectionPressed() {
        #expect(LevelStep.moved(0.53, up: true, steps: 16) == 0.5625)
        #expect(LevelStep.moved(0.53, up: false, steps: 16) == 0.5)
        // Fine from a coarse level lands on the fine grid.
        #expect(LevelStep.moved(0.5625, up: true, steps: 64) == 0.578125)
    }

    @Test func aLevelJustOffTheGridCountsAsOnIt() {
        // CoreAudio hands back 0.5625 as a Float32 that may differ in the last digits.
        #expect(LevelStep.moved(0.562_500_1, up: true, steps: 16) == 0.625)
        #expect(LevelStep.moved(0.562_499_9, up: false, steps: 16) == 0.5)
    }

    @Test func clampsAtBothEnds() {
        #expect(LevelStep.moved(1, up: true, steps: 16) == 1)
        #expect(LevelStep.moved(0.99, up: true, steps: 16) == 1)
        #expect(LevelStep.moved(0, up: false, steps: 16) == 0)
        #expect(LevelStep.moved(0.01, up: false, steps: 16) == 0)
        #expect(LevelStep.moved(1.5, up: true, steps: 16) == 1)
        #expect(LevelStep.moved(-0.5, up: false, steps: 16) == 0)
    }

    @Test func sixteenPressesCoverTheWholeRange() {
        var level: Float = 0
        for _ in 0..<16 { level = LevelStep.moved(level, up: true, steps: LevelStep.coarse) }
        #expect(level == 1)
        for _ in 0..<16 { level = LevelStep.moved(level, up: false, steps: LevelStep.coarse) }
        #expect(level == 0)
    }

    @Test func theStepCountFollowsTheFineModifier() {
        #expect(LevelStep.steps(fine: false) == 16)
        #expect(LevelStep.steps(fine: true) == 64)
    }
}
