import Foundation
import Testing
@testable import PerformanceModule

@Suite struct FanCurveTests {
    // MARK: The curve

    @Test func theFractionRisesEvenlyFromStartToFull() {
        let curve = FanCurve(start: 55, full: 85)
        #expect(curve.fraction(at: 40) == 0 && curve.fraction(at: 55) == 0)
        #expect(curve.fraction(at: 70) == 0.5)
        #expect(curve.fraction(at: 85) == 1 && curve.fraction(at: 99) == 1)
        #expect(abs(curve.fraction(at: 62.5) - 0.25) < 1e-9)
    }

    @Test func theDefaultsAre55And85() {
        #expect(FanCurve.standard == FanCurve(start: 55, full: 85))
    }

    @Test func theTemperaturesAreHeldToTheirRangesAndFullStaysFiveAboveStart() {
        #expect(FanCurve(start: 10, full: 20).normalized == FanCurve(start: 30, full: 40))
        #expect(FanCurve(start: 99, full: 100).normalized == FanCurve(start: 90, full: 100) || FanCurve(start: 99, full: 100).normalized.full - FanCurve(start: 99, full: 100).normalized.start >= 5)
        #expect(FanCurve(start: 60, full: 62).normalized == FanCurve(start: 60, full: 65))
        #expect(FanCurve(start: 55, full: 85).normalized == FanCurve(start: 55, full: 85))
        for start in 0...120 {
            for full in stride(from: 0, through: 120, by: 7) {
                let curve = FanCurve(start: start, full: full).normalized
                #expect(FanCurve.startRange.contains(curve.start) && FanCurve.fullRange.contains(curve.full), "\(start) \(full)")
                #expect(curve.full - curve.start >= FanCurve.minimumGap, "\(start) \(full)")
            }
        }
    }

    @Test func aCurveThatIsNotNormalisedStillGivesAFraction() {
        #expect(FanCurve(start: 60, full: 60).fraction(at: 62.5) == 0.5, "treated as 60 to 65")
    }

    @Test func theFourPresetsAreWhatTheyAreCalled() {
        #expect(FanCurvePreset.allCases.map(\.title) == ["Mặc định Apple", "Mát hơn (50→80)", "Rất mát (45→75)", "Tối đa"])
        #expect(FanCurvePreset.apple.curve == nil)
        #expect(FanCurvePreset.cooler.curve == FanCurve(start: 50, full: 80))
        #expect(FanCurvePreset.veryCool.curve == FanCurve(start: 45, full: 75))
        #expect(FanCurvePreset.maximum.curve == FanCurve(start: 30, full: 40))
        #expect(FanCurvePreset.allCases.compactMap(\.curve).allSatisfy { $0 == $0.normalized })
    }

    @Test func theMaximumPresetIsFullSpeedOnceTheMacIsWarm() {
        let curve = FanCurvePreset.maximum.curve!
        #expect(curve.fraction(at: 40) == 1 && curve.fraction(at: 50) == 1)
    }

    @Test func whichPresetTheSettingsAmountTo() {
        #expect(FanCurvePreset.matching(mode: .apple, curve: .standard) == .apple)
        #expect(FanCurvePreset.matching(mode: .curve, curve: FanCurve(start: 50, full: 80)) == .cooler)
        #expect(FanCurvePreset.matching(mode: .curve, curve: FanCurve(start: 45, full: 75)) == .veryCool)
        #expect(FanCurvePreset.matching(mode: .curve, curve: FanCurve(start: 30, full: 40)) == .maximum)
        #expect(FanCurvePreset.matching(mode: .curve, curve: .standard) == nil, "55 to 85 is the user's own")
    }

    @Test func theTwoModesHaveTheirTitles() {
        #expect(FanMode.allCases == [.apple, .curve])
        #expect(FanMode.apple.title == "Tự động của Apple" && FanMode.curve.title == "Đường cong của tôi")
        #expect(FanMode(rawValue: "curve") == .curve)
    }

    // MARK: The engine

    let start = Date(timeIntervalSinceReferenceDate: 1_000)
    let fans = [
        FanLimits(index: 0, minRPM: 1200, maxRPM: 5779, currentRPM: 2000),
        FanLimits(index: 1, minRPM: 1200, maxRPM: 6241, currentRPM: 2000),
    ]

    /// The engine fed `temperature` for `seconds` at a step of `every`, returning the last directives.
    func run(_ engine: inout FanCurveEngine, temperature: Double, seconds: Double, every: Double = 2, from first: Date? = nil, fans: [FanLimits]? = nil) -> [FanCurveEngine.Directive] {
        var last: [FanCurveEngine.Directive] = []
        var time = first ?? start
        for _ in 0..<Int(seconds / every) {
            last = engine.step(temperature: temperature, at: time, curve: .standard, fans: fans ?? self.fans)
            time = time.addingTimeInterval(every)
        }
        return last
    }

    @Test func belowTheStartTemperatureEveryFanIsLeftToApple() {
        var engine = FanCurveEngine()
        #expect(run(&engine, temperature: 50, seconds: 30) == [.automatic, .automatic])
        #expect(engine.isEngaged == false)
    }

    @Test func atTheStartTheCurveTakesOverAtTheFansMinimum() {
        var engine = FanCurveEngine()
        let directives = run(&engine, temperature: 55, seconds: 2)
        #expect(engine.isEngaged)
        #expect(directives.count == 2)
        // The fraction is 0, so the ideal is the minimum; the rate limit lets it come down from the current 2000 by 800 in a tick.
        #expect(directives == [.rpm(1200), .rpm(1200)])
    }

    @Test func atTheFullTemperatureTheSpeedClimbsToTheMaximumAtMostFourHundredAtATime() {
        var engine = FanCurveEngine()
        var time = start
        var rpms: [Double] = []
        for _ in 0..<40 {
            if case let .rpm(rpm)? = engine.step(temperature: 90, at: time, curve: .standard, fans: [fans[0]]).first { rpms.append(rpm) }
            time = time.addingTimeInterval(1)
        }
        #expect(rpms.first == 2800, "from the fan's own 2000; the first step counts as a two-second tick, which is 800")
        for (before, after) in zip(rpms, rpms.dropFirst()) { #expect(after - before <= 400 + 1e-9) }
        #expect(rpms.last == 5779)
    }

    @Test func theSpeedAlsoComesDownAtMostFourHundredAtATime() {
        var engine = FanCurveEngine()
        var time = start
        var rpms: [Double] = []
        for _ in 0..<12 {
            if case let .rpm(rpm)? = engine.step(temperature: 90, at: time, curve: .standard, fans: [fans[0]]).first { rpms.append(rpm) }
            time = time.addingTimeInterval(1)
        }
        let top = rpms.last ?? 0
        var falling: [Double] = [top]
        for _ in 0..<20 {
            if case let .rpm(rpm)? = engine.step(temperature: 60, at: time, curve: .standard, fans: [fans[0]]).first { falling.append(rpm) }
            time = time.addingTimeInterval(1)
        }
        for (before, after) in zip(falling, falling.dropFirst()) { #expect(before - after <= 400 + 1e-9) }
    }

    @Test func eachFanHasItsOwnRange() {
        var engine = FanCurveEngine()
        let directives = run(&engine, temperature: 120, seconds: 60, every: 1)
        #expect(directives == [.rpm(5779), .rpm(6241)])
    }

    @Test func theTemperatureIsSmoothedSoASpikeBarelyMovesIt() {
        var engine = FanCurveEngine()
        _ = run(&engine, temperature: 50, seconds: 20)
        let before = engine.smoothed ?? 0
        _ = engine.step(temperature: 95, at: start.addingTimeInterval(20), curve: .standard, fans: fans)
        let after = engine.smoothed ?? 0
        #expect(after - before < 0.34 * 45, "one spike of one two-second step moves it by a third at most")
        #expect(after - before > 0)
        #expect(engine.isEngaged == false || after >= 55)
    }

    @Test func theSmoothingSettlesOnASteadyTemperature() {
        var engine = FanCurveEngine()
        _ = run(&engine, temperature: 40, seconds: 10)
        _ = run(&engine, temperature: 80, seconds: 120, from: start.addingTimeInterval(10))
        #expect(abs((engine.smoothed ?? 0) - 80) < 0.1)
    }

    @Test func itLetsGoThreeDegreesBelowTheStartAndNotBefore() {
        var engine = FanCurveEngine()
        _ = run(&engine, temperature: 60, seconds: 60)
        #expect(engine.isEngaged)
        var time = start.addingTimeInterval(100)
        // Settle at 53 (between 52 and 55): still engaged.
        for _ in 0..<60 {
            _ = engine.step(temperature: 53.5, at: time, curve: .standard, fans: fans)
            time = time.addingTimeInterval(2)
        }
        #expect(engine.isEngaged, "53.5 is within the hysteresis band: it stays engaged")
        for _ in 0..<60 {
            _ = engine.step(temperature: 51, at: time, curve: .standard, fans: fans)
            time = time.addingTimeInterval(2)
        }
        #expect(engine.isEngaged == false)
    }

    @Test func itTakesOverAgainOnlyAtTheStartTemperature() {
        var engine = FanCurveEngine()
        _ = run(&engine, temperature: 60, seconds: 20)
        _ = run(&engine, temperature: 40, seconds: 120, from: start.addingTimeInterval(20))
        #expect(engine.isEngaged == false)
        var time = start.addingTimeInterval(200)
        for _ in 0..<60 {
            _ = engine.step(temperature: 54, at: time, curve: .standard, fans: fans)
            time = time.addingTimeInterval(2)
        }
        #expect(engine.isEngaged == false, "54 is below the start: it does not engage")
        for _ in 0..<60 {
            _ = engine.step(temperature: 56, at: time, curve: .standard, fans: fans)
            time = time.addingTimeInterval(2)
        }
        #expect(engine.isEngaged)
    }

    @Test func lettingGoForgetsTheLastSpeedsSoTheNextRiseStartsFromWhereTheFanIs() {
        var engine = FanCurveEngine()
        _ = run(&engine, temperature: 90, seconds: 60, every: 1)
        _ = run(&engine, temperature: 30, seconds: 300, from: start.addingTimeInterval(60))
        #expect(engine.isEngaged == false)
        let cool = [FanLimits(index: 0, minRPM: 1200, maxRPM: 5779, currentRPM: 1800)]
        var time = start.addingTimeInterval(400)
        var first: Double?
        for _ in 0..<40 {
            if case let .rpm(rpm)? = engine.step(temperature: 95, at: time, curve: .standard, fans: cool).first, first == nil { first = rpm }
            time = time.addingTimeInterval(2)
        }
        // The first step after 40 s of silence counts for the longest step, 3 s, which is 1200.
        #expect(first != nil && first! <= 1800 + 1200 + 1e-9, "it starts from the fan's own 1800, not from the old top speed")
    }

    @Test func aLongGapInTimeIsNotALicenceForALongJump() {
        var engine = FanCurveEngine()
        _ = run(&engine, temperature: 90, seconds: 6)
        let before = engine.step(temperature: 90, at: start.addingTimeInterval(6), curve: .standard, fans: [fans[0]])
        let later = engine.step(temperature: 90, at: start.addingTimeInterval(1_000), curve: .standard, fans: [fans[0]])
        guard case let .rpm(a)? = before.first, case let .rpm(b)? = later.first else { Issue.record("expected speeds"); return }
        #expect(b - a <= FanCurveEngine.maxRPMPerSecond * FanCurveEngine.longestStep + 1e-9)
    }

    @Test func resettingStartsFromNothing() {
        var engine = FanCurveEngine()
        _ = run(&engine, temperature: 70, seconds: 20)
        engine.reset()
        #expect(engine.smoothed == nil && engine.isEngaged == false)
    }
}
