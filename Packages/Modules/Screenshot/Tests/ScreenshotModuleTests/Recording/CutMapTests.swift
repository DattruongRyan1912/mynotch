import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct CutMapTests {
    func map(_ cuts: [(Double, Double)], duration: Double = 10) -> CutMap {
        CutMap(duration: duration, cuts: cuts.map { CutRange(start: $0.0, end: $0.1) })
    }

    @Test func withoutCutsEverythingStaysAndTimesAreTheSame() {
        let cuts = map([])

        #expect(cuts.kept == [0..<10] && cuts.editedDuration == 10 && cuts.cuts.isEmpty)
        #expect(cuts.recordingTime(forEdited: 3.5) == 3.5)
        #expect(cuts.editedTime(forRecording: 3.5) == 3.5)
    }

    @Test func aCutInTheMiddleLeavesTwoStretchesAndShiftsWhatFollows() {
        let cuts = map([(2, 5)])

        #expect(cuts.kept == [0..<2, 5..<10])
        #expect(cuts.editedDuration == 7)
        #expect(cuts.recordingTime(forEdited: 1.5) == 1.5)
        #expect(cuts.recordingTime(forEdited: 2.5) == 5.5)
        #expect(cuts.editedTime(forRecording: 6) == 3)
        #expect(cuts.cuts == [CutRange(start: 2, end: 5)])
    }

    @Test func theFirstMomentAfterACutBelongsToWhatFollowsIt() {
        let cuts = map([(2, 5)])

        #expect(cuts.recordingTime(forEdited: 2) == 5)
        #expect(cuts.recordingTime(forEdited: 1.999) != 5)
        #expect(cuts.keptRange(forEdited: 2) == 5..<10)
        #expect(cuts.keptRange(forEdited: 1.9) == 0..<2)
    }

    @Test func aMomentThatWasCutHasNoPlaceInTheEditedVideo() {
        let cuts = map([(2, 5)])

        #expect(cuts.editedTime(forRecording: 2) == nil)
        #expect(cuts.editedTime(forRecording: 4.9) == nil)
        #expect(cuts.editedTime(forRecording: 5) == 2)
        #expect(cuts.editedTime(forRecording: 10) == nil)
    }

    @Test func cutsAtTheStartAndTheEndTrimTheRecording() {
        let cuts = map([(0, 1.5), (9, 10)])

        #expect(cuts.kept == [1.5..<9])
        #expect(cuts.editedDuration == 7.5)
        #expect(cuts.recordingTime(forEdited: 0) == 1.5)
    }

    @Test func cutsInAnyOrderThatOverlapOrTouchAreJoined() {
        let cuts = map([(6, 8), (1, 3), (2.5, 4), (4, 5), (7.5, 9)])

        #expect(cuts.kept == [0..<1, 5..<6, 9..<10])
        #expect(cuts.cuts == [CutRange(start: 1, end: 5), CutRange(start: 6, end: 9)])
        #expect(cuts.editedDuration == 3)
    }

    @Test func cutsBeyondTheRecordingOrNotNumbersAreIgnoredOrTrimmed() {
        let cuts = map([(-5, 1), (9, 40), (.nan, 3), (4, .infinity), (5, 5), (7, 6)])

        #expect(cuts.kept == [1..<9])
    }

    @Test func cuttingEverythingLeavesNothing() {
        let cuts = map([(0, 10)])

        #expect(cuts.kept.isEmpty && cuts.editedDuration == 0)
        #expect(cuts.recordingTime(forEdited: 0) == nil)
        #expect(cuts.cuts == [CutRange(start: 0, end: 10)])
    }

    @Test func timeBeyondTheEndOrBeforeTheStartMapsToNothing() {
        let cuts = map([(2, 5)])

        #expect(cuts.recordingTime(forEdited: 7) == nil)
        #expect(cuts.recordingTime(forEdited: 100) == nil)
        #expect(cuts.recordingTime(forEdited: -1) == nil)
        #expect(cuts.recordingTime(forEdited: .nan) == nil)
    }

    @Test func editedAndRecordingTimeAreInverseWhereTheMomentWasKept() {
        let cuts = map([(1, 2), (3.5, 6), (6.25, 6.5)])

        var time = 0.0
        while time < cuts.editedDuration {
            let recording = cuts.recordingTime(forEdited: time)!
            #expect(abs(cuts.editedTime(forRecording: recording)! - time) < 1e-9)
            time += 0.0625
        }
    }
}
