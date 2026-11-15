import Testing
@testable import FanHelperKit
@testable import PerformanceModule

@Suite struct ThermalSnapshotTests {
    @Test func theHottestSensorIsTheDieTemperature() {
        #expect(DieTemperature.hottest(of: [63.4, 84.4, 70.1]) == 84.4)
        #expect(DieTemperature.hottest(of: [71]) == 71)
    }

    @Test func zeroPlaceholdersAndImplausibleReadingsAreLeftOut() {
        #expect(DieTemperature.hottest(of: [0, 0, 62.5]) == 62.5)
        #expect(DieTemperature.hottest(of: [8.5, 9.9, 70]) == 70)          // Ta05 reads 8.5 on this Mac: not a die
        #expect(DieTemperature.hottest(of: [10, 130]) == 130)
        #expect(DieTemperature.hottest(of: [130.1, 400, 70]) == 70)
        #expect(DieTemperature.hottest(of: [.nan, .infinity, -5, 66]) == 66)
    }

    @Test func noValidReadingIsNoTemperature() {
        #expect(DieTemperature.hottest(of: []) == nil)
        #expect(DieTemperature.hottest(of: [0, 0, 8.5, .nan]) == nil)
    }

    @Test func theSoCIsTheHotterOfTheCPUAndTheGPU() {
        #expect(ThermalSnapshot(cpu: 84, gpu: 69, fans: []).soc == 84)
        #expect(ThermalSnapshot(cpu: 60, gpu: 71, fans: []).soc == 71)
    }

    @Test func theSoCIsWhicheverDieIsKnown() {
        #expect(ThermalSnapshot(cpu: 77, gpu: nil, fans: []).soc == 77)
        #expect(ThermalSnapshot(cpu: nil, gpu: 55, fans: []).soc == 55)
        #expect(ThermalSnapshot(cpu: nil, gpu: nil, fans: []).soc == nil)
    }

    @Test func aFansPlaceBetweenItsLimitsIsAFraction() {
        let fan = FanReading(index: 0, rpm: 3000, minRPM: 1200, maxRPM: 5400)
        #expect(abs(fan.fraction - 1800.0 / 4200.0) < 1e-9)
        #expect(FanReading(index: 0, rpm: 1200, minRPM: 1200, maxRPM: 5400).fraction == 0)
        #expect(FanReading(index: 0, rpm: 5400, minRPM: 1200, maxRPM: 5400).fraction == 1)
    }

    @Test func aFansFractionStaysWithinZeroAndOne() {
        #expect(FanReading(index: 1, rpm: 0, minRPM: 1200, maxRPM: 5400).fraction == 0)       // stopped, below the minimum
        #expect(FanReading(index: 1, rpm: 7000, minRPM: 1200, maxRPM: 5400).fraction == 1)
        #expect(FanReading(index: 1, rpm: 3000, minRPM: 5400, maxRPM: 5400).fraction == 0)    // no range to be in
        #expect(FanReading(index: 1, rpm: 3000, minRPM: 5400, maxRPM: 1200).fraction == 0)
    }
}
