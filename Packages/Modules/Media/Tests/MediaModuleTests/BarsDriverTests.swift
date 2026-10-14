import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import MediaModule

/// When the bars redraw and with what, driven by a manual clock: no view, no real time.
@Suite struct BarsDriverTests {
    struct Frame: Equatable {
        let time: Double
        let levels: [Double]
        let animated: Bool
    }

    final class Frames {
        var all: [Frame] = []
    }

    /// How far the clock runs ahead of the scheduler: a timer that fires late because the main queue was busy.
    final class Skew {
        var seconds = 0.0
    }

    static let epoch = Date(timeIntervalSinceReferenceDate: 1_000)
    let scheduler = ManualScheduler()
    let frames = Frames()
    let skew = Skew()

    func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    var now: Date { Self.epoch + seconds(scheduler.now) }

    func makeDriver() -> BarsDriver {
        let (scheduler, frames, skew) = (scheduler, frames, skew)
        let seconds = seconds
        return BarsDriver(
            scheduler: scheduler, now: { Self.epoch + seconds(scheduler.now) + skew.seconds },
            draw: { levels, animated in frames.all.append(Frame(time: seconds(scheduler.now), levels: levels, animated: animated)) }
        )
    }

    /// A driver that is on screen with something playing, which is what makes the bars move.
    func makePlayingDriver(spectrum: [Float]? = nil) -> BarsDriver {
        let driver = makeDriver()
        driver.setSpectrum(spectrum)
        driver.setPlaying(true)
        driver.setOnScreen(true)
        return driver
    }

    func advance(by duration: Duration) { scheduler.advance(by: duration) }

    // MARK: - Made-up motion

    @Test func madeUpMotionStepsThirtyTimesASecondAndMatchesTheLevelsFunction() {
        let driver = makePlayingDriver()
        defer { driver.setOnScreen(false) }
        advance(by: .seconds(1))
        // One at once, then one per step.
        #expect(frames.all.count == 31)
        for frame in frames.all {
            #expect(frame.levels == NowPlayingBars.levels(spectrum: nil, isPlaying: true, at: Self.epoch + frame.time))
            #expect(!frame.animated)
        }
        let gaps = zip(frames.all, frames.all.dropFirst()).map { $1.time - $0.time }
        #expect(gaps.allSatisfy { abs($0 - 1.0 / 30) < 0.001 })
    }

    // MARK: - The tap's bands

    @Test func bandsDrawAtOnceAndLeaveNothingScheduled() {
        let driver = makePlayingDriver(spectrum: [0.1, 0.2, 0.3, 0.4])
        driver.setSpectrum([0.4, 0.5, 0.6, 0.7].map { Float($0) })
        // A new set a moment later waits for the next slot, and nothing runs after it.
        advance(by: .seconds(1))
        #expect(scheduler.pendingCount == 0)
        #expect(frames.all.last?.levels == [0.4, 0.5, 0.6, 0.7].map { Double(Float($0)) })
    }

    @Test func bandsAreMappedAsBefore() {
        let driver = makePlayingDriver(spectrum: [2, -1])
        #expect(frames.all.last?.levels == [1, 0, 0, 0])
        driver.setSpectrum([0.25, 0.5, 0.75, 1])
        advance(by: .seconds(1))
        #expect(frames.all.last?.levels == [0.25, 0.5, 0.75, 1])
    }

    /// Sets arriving every `gap` seconds for one second, after the driver's first draw.
    func deliver(everySeconds gap: Double, to driver: BarsDriver) {
        frames.all = []
        for step in 1...Int(1 / gap) {
            advance(by: .seconds(gap))
            driver.setSpectrum([Float(step) / 1000, 0.5, 0.5, 0.5])
        }
    }

    func gaps() -> [Double] {
        zip(frames.all, frames.all.dropFirst()).map { $1.time - $0.time }
    }

    /// 25 ms is the gap below which a set waits: a source at exactly that rate is 40 sets a second, all drawn on arrival.
    @Test func aSourceAtTheMinimumGapIsDrawnOnArrivalAtFortyASecond() {
        let driver = makePlayingDriver(spectrum: [0, 0, 0, 0])
        frames.all = []
        for step in 1...40 {
            advance(by: .milliseconds(25))
            driver.setSpectrum([Float(step) / 1000, 0.5, 0.5, 0.5])
            #expect(scheduler.pendingCount == 0, "set \(step) was drawn at once")
        }
        #expect(frames.all.count == 40)
    }

    /// A little faster than that, 41.7 sets a second, is held to the gap: never two draws closer than 25 ms.
    @Test func aSourceJustUnderTheMinimumGapIsHeldToIt() {
        let driver = makePlayingDriver(spectrum: [0, 0, 0, 0])
        deliver(everySeconds: 0.024, to: driver)
        advance(by: .milliseconds(100))
        #expect((38...40).contains(frames.all.filter { $0.time < 1 }.count))
        #expect(gaps().allSatisfy { $0 >= 0.025 - 1e-6 })
        #expect(frames.all.last?.levels.first == Double(Float(41) / 1000))
        #expect(scheduler.pendingCount == 0)
    }

    /// 125 sets a second, three times the tap's rate: held to the same 40 draws a second, the last set still drawn.
    @Test func aSourceFarFasterThanTheCapIsHeldToFortyRedrawsASecond() {
        let driver = makePlayingDriver(spectrum: [0, 0, 0, 0])
        deliver(everySeconds: 0.008, to: driver)
        advance(by: .milliseconds(100))
        let inFirstSecond = frames.all.filter { $0.time < 1 }
        #expect((38...40).contains(inFirstSecond.count))
        #expect(gaps().allSatisfy { $0 >= 0.025 - 1e-6 })
        #expect(frames.all.last?.levels.first == Double(Float(125) / 1000))
        #expect(scheduler.pendingCount == 0)
    }

    /// An early set right after a draw on arrival waits for the gap and no longer, then draws the latest.
    @Test func anEarlySetAfterADrawOnArrivalWaitsForTheGapAndNoLonger() {
        let driver = makePlayingDriver(spectrum: [0, 0, 0, 0])
        advance(by: .milliseconds(40))
        driver.setSpectrum([0.1, 0, 0, 0])
        frames.all = []
        advance(by: .milliseconds(10))
        driver.setSpectrum([0.2, 0, 0, 0])
        #expect(frames.all.isEmpty)
        #expect(scheduler.pendingCount == 1)
        advance(by: .milliseconds(14))
        #expect(frames.all.isEmpty)
        advance(by: .milliseconds(1))
        #expect(frames.all.map(\.levels) == [[Double(Float(0.2)), 0, 0, 0]])
        #expect(abs((frames.all.first?.time ?? 0) - 0.065) < 1e-6)
        #expect(scheduler.pendingCount == 0)
    }

    /// The timer of a waiting set can fire late (a busy main queue). A set that arrives meanwhile, at least the gap after the
    /// last draw, draws at once and takes its place: one draw for the two.
    @Test func aSetThatArrivesBeforeALateTimerDrawsAtOnceInsteadOfIt() {
        let driver = makePlayingDriver(spectrum: [0, 0, 0, 0])
        advance(by: .milliseconds(40))
        driver.setSpectrum([0.1, 0, 0, 0])
        frames.all = []
        advance(by: .milliseconds(10))
        driver.setSpectrum([0.2, 0, 0, 0])
        #expect(scheduler.pendingCount == 1)
        // The waiting set was due at 65 ms; the clock is at 70 ms and its timer has not run.
        skew.seconds = 0.020
        driver.setSpectrum([0.3, 0, 0, 0])
        #expect(frames.all.map(\.levels) == [[Double(Float(0.3)), 0, 0, 0]])
        #expect(scheduler.pendingCount == 0)
        advance(by: .seconds(1))
        #expect(frames.all.count == 1)
    }

    // MARK: - Stalls of the main queue

    /// A tap on its fixed 30 Hz grid with 0 to 5 ms of jitter; `lateSet` reaches the main actor `lateBy` seconds late.
    func tapArrivals(count: Int, lateSet: Int? = nil, lateBy: Double = 0) -> [Double] {
        let jitter = [0, 3, 1, 5, 2, 4, 0, 2, 5, 1].map { Double($0) / 1000 }
        return (1...count).map { Double($0) / 30 + jitter[$0 % jitter.count] + ($0 == lateSet ? lateBy : 0) }
    }

    /// Delivers one set at each time and returns how many were left waiting for a timer.
    func deliver(at arrivals: [Double], to driver: BarsDriver) -> Int {
        var waiting = 0
        for (index, time) in arrivals.enumerated() {
            advance(by: .seconds(time - seconds(scheduler.now)))
            driver.setSpectrum([Float(index + 1) / 1000, 0, 0, 0])
            if scheduler.pendingCount > 0 { waiting += 1 }
        }
        return waiting
    }

    @Test func aSteadyTapNeverWaitsForATimer() {
        let driver = makePlayingDriver(spectrum: [0, 0, 0, 0])
        #expect(deliver(at: tapArrivals(count: 150), to: driver) == 0)
    }

    /// Tap sets reach the main actor through the main queue, so one can come late. The next one is then closer to it than the
    /// gap; its trailing draw must not take the draw time's lag with it, or every later set arrives early again and waits.
    @Test(arguments: [0.010, 0.015, 0.020, 0.030])
    func oneLateSetDoesNotPutTheTapOnATimerForGood(lateBy: Double) {
        let driver = makePlayingDriver(spectrum: [0, 0, 0, 0])
        let waiting = deliver(at: tapArrivals(count: 150, lateSet: 10, lateBy: lateBy), to: driver)
        advance(by: .milliseconds(100))
        #expect(waiting <= 3, "\(waiting) of 150 sets waited")
        #expect(frames.all.last?.levels.first == Double(Float(150) / 1000))
    }

    /// The tap's timer is allowed 5 ms of leeway, so its sets come 28 to 38 ms apart. Each is drawn the moment it arrives,
    /// with nothing scheduled: a timer per set cost a `Task.sleep` and a main-actor hop each, and drift took the rate to 28.
    @Test func aSourceThatJittersAroundThirtyHertzIsDrawnOnArrivalWithoutATimer() {
        let driver = makePlayingDriver(spectrum: [0, 0, 0, 0])
        frames.all = []
        let gaps: [Int] = [28, 38, 31, 35, 29, 37, 30, 36, 28, 38]
        for step in 1...60 {
            advance(by: .milliseconds(gaps[step % gaps.count]))
            driver.setSpectrum([Float(step) / 100, 0, 0, 0])
            #expect(frames.all.count == step, "set \(step) was drawn at once")
            #expect(scheduler.pendingCount == 0, "nothing waits for a slot after set \(step)")
        }
        #expect(frames.all.compactMap { $0.levels.first } == (1...60).map { Double(Float($0) / 100) })
        // Drawn on arrival: 60 sets over about two seconds, 30 a second.
        let span = (frames.all.last?.time ?? 0) - (frames.all.first?.time ?? 0)
        #expect(abs(span / 59 - 1.0 / 30) < 0.002)
    }

    @Test func identicalLevelsAreNotDrawnAgain() {
        let driver = makePlayingDriver(spectrum: [0.3, 0.3, 0.3, 0.3])
        let drawn = frames.all.count
        driver.setSpectrum([0.3, 0.3, 0.3, 0.3])
        advance(by: .seconds(1))
        #expect(frames.all.count == drawn)
    }

    @Test func theTapStoppingFallsBackToTheMadeUpMotion() {
        let driver = makePlayingDriver(spectrum: [0.5, 0.5, 0.5, 0.5])
        frames.all = []
        driver.setSpectrum(nil)
        advance(by: .seconds(1))
        #expect(frames.all.count >= 30)
        for frame in frames.all {
            #expect(frame.levels == NowPlayingBars.levels(spectrum: nil, isPlaying: true, at: Self.epoch + frame.time))
        }
    }

    @Test func theTapStartingStopsTheMadeUpMotion() {
        let driver = makePlayingDriver()
        advance(by: .milliseconds(200))
        driver.setSpectrum([0.5, 0.5, 0.5, 0.5])
        frames.all = []
        advance(by: .seconds(1))
        // Only the bands' own draw, which waited for its slot: no steps of made-up motion follow.
        #expect(frames.all.map(\.levels) == [[0.5, 0.5, 0.5, 0.5]])
        #expect(scheduler.pendingCount == 0)
    }

    // MARK: - Pausing

    @Test func pausingEasesTheBarsToRestAndStopsEverything() {
        let driver = makePlayingDriver()
        advance(by: .milliseconds(100))
        frames.all = []
        driver.setPlaying(false)
        #expect(frames.all == [Frame(time: 0.1, levels: [0, 0, 0, 0], animated: true)])
        advance(by: .seconds(5))
        #expect(frames.all.count == 1)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func resumingMovesTheBarsAgainWithoutAnimatingTheFirstFrame() {
        let driver = makePlayingDriver()
        driver.setPlaying(false)
        frames.all = []
        driver.setPlaying(true)
        #expect(frames.all.count == 1)
        #expect(frames.all[0].animated == false)
        advance(by: .milliseconds(100))
        #expect(frames.all.count == 4)
    }

    @Test func barsThatNeverPlayedDrawTheirRestOnceOnScreen() {
        let driver = makeDriver()
        driver.setOnScreen(true)
        #expect(frames.all == [Frame(time: 0, levels: [0, 0, 0, 0], animated: false)])
    }

    // MARK: - Off screen

    @Test func nothingIsDrawnOrScheduledWhileOffScreen() {
        let driver = makeDriver()
        driver.setPlaying(true)
        driver.setSpectrum([0.5, 0.5, 0.5, 0.5])
        driver.setSpectrum([0.6, 0.5, 0.5, 0.5])
        driver.setPlaying(false)
        driver.setPlaying(true)
        advance(by: .seconds(5))
        #expect(frames.all.isEmpty)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func leavingTheScreenStopsTheMotionAtOnce() {
        let driver = makePlayingDriver()
        advance(by: .milliseconds(100))
        driver.setOnScreen(false)
        let drawn = frames.all.count
        #expect(scheduler.pendingCount == 0)
        advance(by: .seconds(5))
        #expect(frames.all.count == drawn)
    }

    @Test func leavingTheScreenWithAPendingDrawCancelsIt() {
        let driver = makePlayingDriver(spectrum: [0, 0, 0, 0])
        driver.setSpectrum([0.5, 0, 0, 0])
        #expect(scheduler.pendingCount == 1)
        driver.setOnScreen(false)
        #expect(scheduler.pendingCount == 0)
    }

    @Test func comingBackDrawsTheCurrentStateAtOnce() {
        let driver = makePlayingDriver(spectrum: [0.1, 0.2, 0.3, 0.4])
        driver.setOnScreen(false)
        driver.setSpectrum([0.9, 0.8, 0.7, 0.6])
        frames.all = []
        driver.setOnScreen(true)
        #expect(frames.all.last?.levels == [0.9, 0.8, 0.7, 0.6].map { Double(Float($0)) })
        #expect(scheduler.pendingCount == 0)
    }
}
