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

    static let epoch = Date(timeIntervalSinceReferenceDate: 1_000)
    let scheduler = ManualScheduler()
    let frames = Frames()

    func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    var now: Date { Self.epoch + seconds(scheduler.now) }

    func makeDriver() -> BarsDriver {
        let (scheduler, frames) = (scheduler, frames)
        let seconds = seconds
        return BarsDriver(
            scheduler: scheduler, now: { Self.epoch + seconds(scheduler.now) },
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

    @Test func aFasterSourceStillRedrawsAtMostThirtyTimesASecond() {
        let driver = makePlayingDriver(spectrum: [0, 0, 0, 0])
        frames.all = []
        // 120 sets a second, each different.
        for step in 1...120 {
            advance(by: .milliseconds(1000.0 / 120 - 0.0001))
            driver.setSpectrum([Float(step) / 200, 0.5, 0.5, 0.5])
        }
        advance(by: .milliseconds(100))
        let inFirstSecond = frames.all.filter { $0.time < 1 }
        #expect(inFirstSecond.count <= 31)
        #expect(inFirstSecond.count >= 28)
        // The last set is not lost: it is the last picture.
        #expect(frames.all.last?.levels == [Double(Float(120) / 200), 0.5, 0.5, 0.5])
        #expect(scheduler.pendingCount == 0)
    }

    /// The tap's timer jitters around 30 Hz, so some sets arrive a little early and have to wait for their slot; none is lost.
    @Test func aSourceThatJittersAroundThirtyHertzLosesNothing() {
        let driver = makePlayingDriver(spectrum: [0, 0, 0, 0])
        frames.all = []
        for step in 1...60 {
            advance(by: step.isMultiple(of: 2) ? .microseconds(34_667) : .milliseconds(32))
            driver.setSpectrum([Float(step) / 100, 0, 0, 0])
        }
        advance(by: .milliseconds(100))
        #expect(frames.all.compactMap { $0.levels.first } == (1...60).map { Double(Float($0) / 100) })
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
