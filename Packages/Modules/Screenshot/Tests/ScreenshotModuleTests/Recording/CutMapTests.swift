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

    @Test func editedAndRecordingTimeAreInverseWhereTheMomentWasKept() throws {
        let cuts = map([(1, 2), (3.5, 6), (6.25, 6.5)])

        var time = 0.0
        while time < cuts.editedDuration {
            let recording = try #require(cuts.recordingTime(forEdited: time))
            let back = try #require(cuts.editedTime(forRecording: recording))
            #expect(abs(back - time) < 1e-9)
            time += 0.0625
        }
    }

    @Test func aTimeJustPastTheEndOrBeforeTheStartIsTheNearestMomentNotNothing() throws {
        let cuts = map([(2, 5)])

        // The composition can be microseconds longer than the kept stretches: a frame there is the last moment.
        let past = try #require(cuts.nearest(toEdited: cuts.editedDuration + 0.000_001))
        #expect(past.range == 5..<10 && past.time <= 10 && past.time > 9.999)
        let atEnd = try #require(cuts.nearest(toEdited: cuts.editedDuration))
        #expect(atEnd.range == 5..<10 && atEnd.time <= 10 && atEnd.time > 9.999)
        let before = try #require(cuts.nearest(toEdited: -1))
        #expect(before.time == 0 && before.range == 0..<2)
        // Inside the video it is the same answer as the exact one.
        let inside = try #require(cuts.nearest(toEdited: 3))
        #expect(inside.time == cuts.recordingTime(forEdited: 3) && inside.range == 5..<10)
        #expect(cuts.nearest(toEdited: .nan) == nil)
        #expect(map([(0, 10)]).nearest(toEdited: 0) == nil)
    }
}
