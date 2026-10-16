import Foundation
import Testing
@testable import PerformanceModule

@Suite struct ThermalHistoryTests {
    let start = Date(timeIntervalSinceReferenceDate: 1_000)

    func history(_ values: [(Double, TimeInterval)]) -> ThermalHistory {
        var history = ThermalHistory()
        for (value, offset) in values { history.append(value, at: start.addingTimeInterval(offset)) }
        return history
    }

    @Test func keepsTheLastTwoMinutes() {
        let history = history([(60, 0), (61, 60), (62, 119), (63, 121), (64, 130)])
        // Measured from the newest (130): the sample at 0 is 130 s old and goes; the one at 60 is 70 s old and stays.
        #expect(history.samples.map(\.value) == [61, 62, 63, 64])
    }

    @Test func aSampleExactlyTwoMinutesOldStays() {
        let history = history([(60, 0), (70, 120)])
        #expect(history.samples.map(\.value) == [60, 70])
    }

    @Test func aLongPauseLeavesOnlyTheNewSample() {
        let history = history([(60, 0), (61, 2), (62, 4), (80, 600)])
        #expect(history.samples.map(\.value) == [80])
    }

    @Test func aClockThatWentBackStartsAgain() {
        let history = history([(60, 100), (61, 102), (70, 50)])
        #expect(history.samples.map(\.value) == [70])
    }

    @Test func removingAllLeavesNothing() {
        var history = history([(60, 0), (61, 2)])
        history.removeAll()
        #expect(history.samples.isEmpty)
    }

    @Test func samplesCloseTogetherAreOneRun() {
        let runs = history([(60, 0), (61, 2), (62, 4)]).runs(maxGap: 5)
        #expect(runs.map { $0.map(\.value) } == [[60, 61, 62]])
    }

    @Test func aGapLongerThanTheLimitSplitsTheRunSoNothingIsDrawnAcrossIt() {
        // The tab was closed for 40 s: the old samples are still inside the two minutes, but the line must not join them to the new ones.
        let runs = history([(60, 0), (61, 2), (62, 4), (70, 44), (71, 46)]).runs(maxGap: 5)
        #expect(runs.map { $0.map(\.value) } == [[60, 61, 62], [70, 71]])
    }

    @Test func aGapExactlyAsLongAsTheLimitDoesNotSplit() {
        let runs = history([(60, 0), (61, 5)]).runs(maxGap: 5)
        #expect(runs.count == 1)
    }

    @Test func noSamplesIsNoRuns() {
        #expect(ThermalHistory().runs(maxGap: 5).isEmpty)
    }

    @Test func theNewestSampleIsAtTheRightEdgeAndTheOldestPossibleAtTheLeft() throws {
        let history = history([(60, 0), (61, 60), (62, 120)])
        let positions = history.samples.map { history.position(of: $0) }
        #expect(positions == [0, 0.5, 1])
    }

    @Test func aShortHistoryStartsPartwayAcrossAndEndsAtTheRightEdge() {
        let history = history([(60, 0), (61, 30)])
        #expect(history.samples.map { history.position(of: $0) } == [0.75, 1])
    }

    @Test func theScaleCoversTheValuesWithAtLeastTenDegrees() throws {
        let flat = history([(60, 0), (60, 2)])
        let range = try #require(flat.scale)
        #expect(range.upperBound - range.lowerBound == ThermalHistory.minimumSpan)
        #expect(range.contains(60))
        let rising = history([(55, 0), (85, 2)])
        let wide = try #require(rising.scale)
        #expect(wide.lowerBound <= 55 && wide.upperBound >= 85)
        #expect(ThermalHistory().scale == nil)
    }
}
