import CoreGraphics
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

/// A separator on the macOS 27 bar: laid out up to `limit` points, its right edge staying put; dropped beyond it, placed by
/// itself so that the edge jumps right by its length.
final class FakeLengthProbe: MenuBarLengthProbe {
    var length: CGFloat = -1 { didSet { lengths.append(length) } }
    private(set) var lengths: [CGFloat] = []
    var limit: CGFloat = 900
    var edge: CGFloat = 1_400
    var room: CGFloat? = 1_400
    var hasWindow = true

    var trailingEdge: CGFloat? {
        guard hasWindow else { return nil }
        return length > limit ? edge + length : edge
    }
}

@Suite struct MenuBarFittedLengthTests {
    private struct Rig {
        let probe = FakeLengthProbe()
        let scheduler = ManualScheduler()
        let fitted: MenuBarFittedLength

        init() {
            fitted = MenuBarFittedLength(probe: probe, scheduler: scheduler, normalLength: -1)
        }

        /// Long enough for a whole measurement: a dozen probes.
        func settle() { scheduler.advance(by: MenuBarFittedLength.settleDelay * 20) }
    }

    @Test func aLongSeparatorIsMeasuredThenGetsTheLengthThatFitsLessTheMargin() {
        let rig = Rig()
        rig.fitted.apply(long: true)
        #expect(rig.fitted.isMeasuring)
        rig.settle()
        #expect(!rig.fitted.isMeasuring)
        let fitted = try! #require(rig.fitted.fitted)
        // Within the precision under the limit, less the margin.
        #expect(fitted <= 900 - MenuBarFittedLength.margin)
        #expect(fitted >= 900 - MenuBarFittedLength.precision - MenuBarFittedLength.margin)
        #expect(rig.probe.length == fitted)
        // No probe went past the room the separator has on its display.
        #expect(rig.probe.lengths.allSatisfy { $0 <= 1_400 })
    }

    @Test func theMeasuredLengthIsKeptForTheNextCollapse() {
        let rig = Rig()
        rig.fitted.apply(long: true)
        rig.settle()
        let fitted = rig.fitted.fitted
        rig.fitted.apply(long: false)
        #expect(rig.probe.length == -1)
        let probes = rig.probe.lengths.count
        rig.fitted.apply(long: true)
        #expect(rig.probe.length == fitted)
        rig.settle()
        // One write, and no measurement.
        #expect(rig.probe.lengths.count == probes + 1)
    }

    @Test func goingNormalDuringTheMeasurementStopsItAndLeavesTheSeparatorNormal() {
        let rig = Rig()
        rig.fitted.apply(long: true)
        rig.scheduler.advance(by: MenuBarFittedLength.settleDelay * 3)
        rig.fitted.apply(long: false)
        rig.settle()
        #expect(!rig.fitted.isMeasuring)
        #expect(rig.probe.length == -1)
        #expect(rig.fitted.fitted == nil)
    }

    @Test func whenNothingFitsTheSeparatorStaysNormal() {
        let rig = Rig()
        rig.probe.limit = 10
        rig.fitted.apply(long: true)
        rig.settle()
        #expect(rig.fitted.fitted == nil)
        #expect(rig.probe.length == -1)
    }

    @Test func withoutAWindowNothingIsMeasured() {
        let rig = Rig()
        rig.probe.hasWindow = false
        rig.fitted.apply(long: true)
        rig.settle()
        #expect(rig.fitted.fitted == nil)
        #expect(rig.probe.length == -1)
    }

    @Test func aSeparatorDroppedAfterAnAppAddedAnIconIsMeasuredAgainOnceTheCooldownIsOver() {
        let rig = Rig()
        rig.fitted.apply(long: true)
        rig.settle()
        rig.scheduler.advance(by: MenuBarFittedLength.remeasureCooldown)
        // Another app's icon takes room: the length that fitted is now too long.
        rig.probe.limit = 700
        rig.fitted.layoutChanged()
        rig.settle()
        let fitted = try! #require(rig.fitted.fitted)
        #expect(fitted <= 700 - MenuBarFittedLength.margin)
        #expect(rig.probe.length == fitted)
    }

    @Test func aDroppedSeparatorIsNotMeasuredAgainDuringTheCooldown() {
        let rig = Rig()
        rig.fitted.apply(long: true)
        rig.settle()
        let fitted = rig.fitted.fitted
        rig.probe.limit = 700
        rig.fitted.layoutChanged()
        rig.settle()
        #expect(rig.fitted.fitted == fitted)
    }

    @Test func aSeparatorStillLaidOutIsLeftAlone() {
        let rig = Rig()
        rig.fitted.apply(long: true)
        rig.settle()
        rig.scheduler.advance(by: MenuBarFittedLength.remeasureCooldown)
        let probes = rig.probe.lengths.count
        rig.fitted.layoutChanged()
        rig.fitted.layoutChanged()
        rig.settle()
        #expect(rig.probe.lengths.count == probes)
    }

    @Test func newDisplaysAreMeasuredAgainWhileLongAndOnlyForgottenWhileNormal() {
        let rig = Rig()
        rig.fitted.apply(long: true)
        rig.settle()
        rig.probe.limit = 1_200
        rig.fitted.forget()
        #expect(rig.fitted.isMeasuring)
        rig.settle()
        #expect(try! #require(rig.fitted.fitted) > 1_000)

        rig.fitted.apply(long: false)
        rig.fitted.forget()
        #expect(!rig.fitted.isMeasuring)
        #expect(rig.fitted.fitted == nil)
    }

    @Test func eachMeasurementIsAnnounced() {
        let rig = Rig()
        var count = 0
        rig.fitted.onMeasured = { count += 1 }
        rig.fitted.apply(long: true)
        rig.settle()
        #expect(count == 1)
    }
}
