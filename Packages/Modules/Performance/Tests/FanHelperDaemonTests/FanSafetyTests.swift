import Testing
@testable import FanHelperDaemon

@Suite struct FanSafetyTests {
    @Test func aSpeedIsHeldToTheRange() {
        #expect(FanSafety.clamp(3000, min: 1200, max: 5779) == 3000)
        #expect(FanSafety.clamp(100, min: 1200, max: 5779) == 1200)
        #expect(FanSafety.clamp(9000, min: 1200, max: 5779) == 5779)
        #expect(FanSafety.clamp(1200, min: 1200, max: 5779) == 1200 && FanSafety.clamp(5779, min: 1200, max: 5779) == 5779)
    }

    func decide(_ requested: Double, baseline: Double? = 2000, temperature: Double? = 60, baselineTemperature: Double? = 60) -> FanSafety.ForcedDecision {
        FanSafety.forcedDecision(
            requested: requested, baseline: baseline, dieTemperature: temperature, baselineTemperature: baselineTemperature, drift: 4
        )
    }

    @Test func aSpeedAtOrAboveAppleIsForced() {
        #expect(decide(2000) == .force(2000))
        #expect(decide(3500) == .force(3500))
    }

    @Test func aSpeedBelowAppleStaysAutomatic() {
        #expect(decide(1999) == .automatic("Apple's own speed is higher"))
    }

    @Test func withoutApplesSpeedNothingIsForced() {
        #expect(decide(3000, baseline: nil) == .automatic("Apple's own speed cannot be read"))
    }

    @Test func aDieThatGotHotterThanWhenApplesSpeedWasReadIsNotTrusted() {
        #expect(decide(3000, temperature: 64, baselineTemperature: 60) == .force(3000), "exactly the drift is still fine")
        #expect(decide(3000, temperature: 64.5, baselineTemperature: 60) == .automatic("hotter than when Apple's speed was read"))
    }

    @Test func aCoolerDieKeepsTheBaseline() {
        #expect(decide(3000, temperature: 50, baselineTemperature: 60) == .force(3000))
    }

    @Test func anUnknownTemperatureLeavesItToTheBaselineAlone() {
        #expect(decide(3000, temperature: nil) == .force(3000))
        #expect(decide(1000, temperature: nil) == .automatic("Apple's own speed is higher"))
    }

    @Test func theGuardTripsAtNinetyFiveAndLetsGoBelowNinety() {
        func next(_ active: Bool, _ t: Double) -> Bool { FanSafety.guardNext(active: active, temperature: t, trip: 95, release: 90) }
        #expect(next(false, 94.9) == false)
        #expect(next(false, 95) == true)
        #expect(next(true, 94) == true && next(true, 90) == true, "between the two it stays as it was")
        #expect(next(true, 89.9) == false)
        #expect(next(false, 92) == false)
        #expect(next(true, 120) == true)
    }
}
