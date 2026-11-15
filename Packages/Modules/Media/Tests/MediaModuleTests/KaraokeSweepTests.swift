import AppKit
import Testing
@testable import MediaModule

/// The maths of the sweep: how far a line is sung at a moment, and the moves that follow. Every letter is 10 points wide.
@Suite struct KaraokeSweepTests {
    func word(_ text: String, _ begin: Double, _ end: Double) -> LyricWord { LyricWord(text: text, begin: begin, end: end) }

    /// "one " 1…2 s, "two " 2…3 s, then a pause, "three" 3.5…4.5 s.
    let words = [LyricWord(text: "one ", begin: 1, end: 2), LyricWord(text: "two ", begin: 2, end: 3), LyricWord(text: "three", begin: 3.5, end: 4.5)]
    let edges: [Double] = [0, 40, 80, 130]

    func sweep(at position: Double, rate: Double = 1) -> KaraokeSweep {
        KaraokeSweep.make(words: words, edges: edges, position: position, rate: rate)
    }

    func step(_ duration: Double, _ x: Double) -> KaraokeSweep.Step { KaraokeSweep.Step(duration: duration, x: x) }

    // MARK: a word

    @Test func aWordIsSungEvenlyBetweenItsBeginAndItsEnd() {
        let word = word("la", 2, 4)
        #expect(word.progress(at: 1) == 0)
        #expect(word.progress(at: 2) == 0)
        #expect(word.progress(at: 2.5) == 0.25)
        #expect(word.progress(at: 3) == 0.5)
        #expect(word.progress(at: 4) == 1)
        #expect(word.progress(at: 99) == 1)
    }

    @Test func aWordWithNoLengthIsSungInAnInstant() {
        let word = word("la", 2, 2)
        #expect(word.progress(at: 1.999) == 0)
        #expect(word.progress(at: 2) == 1)
        #expect(word.progress(at: 3) == 1)
    }

    @Test func aPositionThatIsNotANumberIsNothingSung() {
        #expect(word("la", 2, 4).progress(at: .nan) == 0)
        #expect(word("la", 2, 2).progress(at: .nan) == 0)
    }

    // MARK: where the fill is

    @Test func beforeTheFirstWordNothingIsFilledAndTheSweepWaitsForIt() {
        let sweep = sweep(at: 0)
        #expect(sweep.start == 0)
        #expect(sweep.steps == [step(1, 0), step(1, 40), step(1, 80), step(0.5, 80), step(1, 130)])
    }

    @Test func insideAWordTheFillIsPartWayAcrossIt() {
        let sweep = sweep(at: 1.5)
        #expect(sweep.start == 20)
        #expect(sweep.steps == [step(0.5, 40), step(1, 80), step(0.5, 80), step(1, 130)])
        // 2.5 s: half of "two ", which is 60 of the line's 130 points.
        #expect(self.sweep(at: 2.5).start == 60)
        #expect(self.sweep(at: 2.5).start / 130 == 60.0 / 130)
    }

    @Test func inAPauseBetweenWordsTheFillHoldsAtTheEndOfTheWordBefore() {
        let sweep = sweep(at: 3.25)
        #expect(sweep.start == 80)
        #expect(sweep.steps == [step(0.25, 80), step(1, 130)])
    }

    @Test func atTheEndOfAWordItIsFilledAndTheNextWordIsNext() {
        let sweep = sweep(at: 2)
        #expect(sweep.start == 40)
        #expect(sweep.steps == [step(1, 80), step(0.5, 80), step(1, 130)])
    }

    @Test func afterTheLastWordTheWholeLineIsFilledAndNothingMoves() {
        for position in [4.5, 5, 999] {
            let sweep = sweep(at: position)
            #expect(sweep.start == 130)
            #expect(sweep.steps.isEmpty)
            #expect(sweep.finish == 130)
        }
    }

    @Test func theSweepEndsWithTheWholeLineFilledAndTakesAsLongAsTheSong() {
        let sweep = sweep(at: 0)
        #expect(sweep.finish == 130)
        #expect(abs(sweep.duration - 4.5) < 1e-9)
        #expect(abs(self.sweep(at: 3.25).duration - 1.25) < 1e-9)
    }

    @Test func theFillNeverMovesBackwards() {
        var fill = -1.0
        for position in stride(from: -1.0, through: 6, by: 0.05) {
            let start = sweep(at: position).start
            #expect(start >= fill)
            fill = start
        }
        #expect(fill == 130)
    }

    // MARK: the clock

    @Test func aFasterClockMakesEveryStepShorter() {
        let sweep = sweep(at: 1.5, rate: 2)
        #expect(sweep.start == 20)
        #expect(sweep.steps == [step(0.25, 40), step(0.5, 80), step(0.25, 80), step(0.5, 130)])
    }

    @Test func aSlowerClockMakesThemLonger() {
        #expect(sweep(at: 1.5, rate: 0.5).steps == [step(1, 40), step(2, 80), step(1, 80), step(2, 130)])
    }

    @Test func aClockThatStandsStillOrRunsBackwardsLeavesTheFillWhereItIs() {
        for rate in [0.0, -1, .nan] {
            let sweep = sweep(at: 1.5, rate: rate)
            #expect(sweep.start == 20)
            #expect(sweep.steps.isEmpty)
        }
    }

    @Test func aSeekIsANewSweepFromWhereItLands() {
        // Playing at 1.5 s, then the position jumps back to 0.2 s and forward to 4 s: each is made from its own position.
        #expect(sweep(at: 1.5).start == 20)
        #expect(sweep(at: 0.2).start == 0)
        #expect(sweep(at: 0.2).steps.first?.x == 0)
        #expect(abs((sweep(at: 0.2).steps.first?.duration ?? 0) - 0.8) < 1e-9)
        // Half of "three", which is 25 of its 50 points.
        #expect(sweep(at: 4).start == 105)
    }

    @Test func aPositionThatIsNotANumberLeavesTheLineEmpty() {
        let sweep = sweep(at: .nan)
        #expect(sweep.start == 0)
        #expect(sweep.steps.isEmpty)
    }

    // MARK: the animation's key times

    @Test func theKeyTimesShareTheSweepOutByHowLongEachStepTakes() {
        let times = sweep(at: 0).keyTimes
        #expect(times.count == 6)
        #expect(times.first == 0 && times.last == 1)
        let expected = [0, 1, 2, 3, 3.5, 4.5].map { $0 / 4.5 }
        for (time, expected) in zip(times, expected) { #expect(abs(time - expected) < 1e-9) }
    }

    @Test func theKeyTimesNeverGoBackwards() {
        for position in stride(from: -1.0, through: 4.4, by: 0.37) {
            let times = sweep(at: position).keyTimes
            #expect(zip(times, times.dropFirst()).allSatisfy { $0 <= $1 })
            #expect(times.isEmpty || (times.first == 0 && times.last == 1))
        }
    }

    @Test func aSweepWithNoStepsHasNoKeyTimes() {
        #expect(sweep(at: 9).keyTimes.isEmpty)
        #expect(sweep(at: 1.5, rate: 0).keyTimes.isEmpty)
    }

    // MARK: words with no length

    @Test func aWordWithNoLengthJumpsInAStepTooShortToSee() {
        let words = [word("a ", 1, 1), word("b", 1, 2)]
        let sweep = KaraokeSweep.make(words: words, edges: [0, 20, 30], position: 0.5, rate: 1)
        #expect(sweep.start == 0)
        #expect(sweep.steps == [step(0.5, 0), step(KaraokeSweep.minimumStep, 20), step(1, 30)])
    }

    @Test func noWordsOrEdgesThatDoNotMatchThemGiveAnEmptySweep() {
        #expect(KaraokeSweep.make(words: [], edges: [0], position: 1, rate: 1) == KaraokeSweep(start: 0, steps: []))
        #expect(KaraokeSweep.make(words: words, edges: [0, 40], position: 1, rate: 1) == KaraokeSweep(start: 0, steps: []))
    }

    // MARK: the soft edge

    @Test func theSoftEdgeStartsBeforeTheTextAndEndsOnItsLastLetter() {
        #expect(KaraokeSweep.edge(forFill: 0, width: 100, feather: 8) == -8)
        #expect(KaraokeSweep.edge(forFill: 100, width: 100, feather: 8) == 100)
        #expect(KaraokeSweep.edge(forFill: 50, width: 100, feather: 8) == 46)
    }

    @Test func aTextOfNoWidthHasNoEdgeToMove() {
        #expect(KaraokeSweep.edge(forFill: 0, width: 0, feather: 8) == 0)
    }

    // MARK: the fill of a line whose edges do not run left to right

    @Test func edgesThatDoNotNeverDecreaseLeaveTheWholeLineFilledAndNothingMoving() {
        // Right-to-left text measures its word starts from the right: the fill would run backwards.
        let backwards: [Double] = [103.4, 72.6, 35.8, 103.4]
        for position in [0.0, 1.5, 2.5, 99] {
            let sweep = KaraokeSweep.make(words: words, edges: backwards, position: position, rate: 1)
            #expect(sweep == KaraokeSweep(start: 103.4, steps: []))
        }
        #expect(KaraokeSweep.make(words: words, edges: [0, 40, 30, 130], position: 1.5, rate: 1).steps.isEmpty)
        #expect(KaraokeSweep.make(words: words, edges: [0, .nan, 80, 130], position: 1.5, rate: 1).steps.isEmpty)
    }

    @Test func edgesThatRunLeftToRightAreNeverMistakenForBackwardsOnes() {
        #expect(!sweep(at: 1.5).steps.isEmpty)
        // Two words that start at the same place (one with no width) are fine.
        let equal = KaraokeSweep.make(words: [word("a", 1, 2), word("b", 2, 3)], edges: [0, 0, 10], position: 0, rate: 1)
        #expect(!equal.steps.isEmpty)
    }

    // MARK: fitting a line in a row

    /// Wider than the size says, the smaller it gets: the way a font's tracking behaves.
    func tight(_ size: Double) -> Double { size * (10 + 0.05 * (20 - size)) }

    @Test func aLineThatFitsKeepsItsSize() {
        #expect(KaraokeFit.size(base: 12, available: 300) { $0 * 10 } == 12)
        #expect(KaraokeFit.size(base: 12, available: 121) { $0 * 10 } == 12)
    }

    @Test func aLineTooWideIsShrunkUntilItFitsAsMeasuredAtThatSize() {
        // Linear: one step.
        #expect(KaraokeFit.size(base: 20, available: 131) { $0 * 10 } == 13)
        // Wider at a smaller size: the size is found by measuring again, not by scaling the first measurement.
        let size = KaraokeFit.size(base: 20, available: 131, measure: tight)
        #expect(size < 20 && size >= 20 * KaraokeFit.minimumScale)
        #expect(tight(size) <= 130.5)
        // What scaling the first measurement would give does not fit.
        #expect(tight(20 * 130.0 / tight(20)) > 131)
    }

    @Test func aLineThatFitsByAHairIsShrunkAHair() {
        // A text layer may measure a little wider than CoreText, so it is given a point of room.
        let size = KaraokeFit.size(base: 12, available: 120.5) { $0 * 10 }
        #expect(size < 12)
        #expect(size * 10 <= 119.5 + 1e-9)
    }

    @Test func nothingShrinksBelowTheLimitAndAnEmptyRowGetsTheLimit() {
        #expect(KaraokeFit.size(base: 20, available: 10) { $0 * 10 } == 20 * KaraokeFit.minimumScale)
        #expect(KaraokeFit.size(base: 20, available: 0) { $0 * 10 } == 20 * KaraokeFit.minimumScale)
        #expect(KaraokeFit.size(base: 20, available: -5) { $0 * 10 } == 20 * KaraokeFit.minimumScale)
    }

    @Test func aSizeIsFoundInAFewMeasurements() {
        var measurements = 0
        _ = KaraokeFit.size(base: 20, available: 131) { size in
            measurements += 1
            return tight(size)
        }
        #expect(measurements <= 5)
    }

    // MARK: direction

    @Test(arguments: ["مرحبا بالعالم الجميل", "שלום עולם", "hello مرحبا world", "hello שלום", "שלום hello", "ٱلْحَمْدُ لِلَّٰهِ"])
    func aLineWithARightToLeftRunIsFound(text: String) {
        #expect(KaraokeFit.hasRightToLeftRun(text, font: .systemFont(ofSize: 12)))
    }

    @Test(arguments: ["one two three", "Tôi yêu em người ơi", "こんにちは 世界", "한국어 가사", "1, 2, 3: go!", "", " "])
    func aLeftToRightLineIsNotMistakenForOne(text: String) {
        #expect(!KaraokeFit.hasRightToLeftRun(text, font: .systemFont(ofSize: 12)))
    }
}
