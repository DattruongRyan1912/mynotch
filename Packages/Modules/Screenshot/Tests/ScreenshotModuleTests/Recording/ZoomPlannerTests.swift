import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct ZoomPlannerTests {
    static let width = 1920, height = 1080

    typealias Spot = (t: Double, x: Double, y: Double)

    func track(clicks: [Spot] = [], moves: [Spot] = [], keys: [Double] = [], keyboard: Bool = true) -> ActivityTrack {
        ActivityTrack(
            pixelWidth: Self.width, pixelHeight: Self.height, keyboardRecorded: keyboard,
            pointer: moves.map { .init(t: $0.t, x: $0.x, y: $0.y) },
            clicks: clicks.map { .init(t: $0.t, x: $0.x, y: $0.y, button: .left) },
            keys: keys
        )
    }

    /// A pointer that moves in a straight line along x, one sample every `interval` seconds.
    func walk(count: Int, from start: Double, every interval: Double, step: Double, x0: Double, y: Double) -> [Spot] {
        var spots: [Spot] = []
        for index in 0..<count {
            let n = Double(index)
            spots.append((start + n * interval, x0 + n * step, y))
        }
        return spots
    }

    @Test func aRecordingWithNothingInItHasNoZoom() {
        #expect(ZoomPlanner.plan(activity: track()).isEmpty)
    }

    @Test func aClickZoomsInFromTheClickUntilTheIdleTimeoutAfterIt() throws {
        let plan = ZoomPlanner.plan(activity: track(clicks: [(2, 400, 300)]))

        let segment = try #require(plan.first)
        #expect(plan.count == 1)
        #expect(segment.start == 2 && segment.end == 3.5 && segment.scale == 2 && !segment.manual)
        #expect(segment.focus == [.init(t: 2, x: 400, y: 300)])
    }

    @Test func movingThePointerOrTypingNeverStartsAZoom() {
        let activity = track(moves: [(1, 10, 10), (2, 400, 300), (3, 900, 500)], keys: [1, 2, 3])

        #expect(ZoomPlanner.plan(activity: activity).isEmpty)
    }

    @Test func byDefaultCameraStaysOnTheClickAndMovesDoNotKeepZoom() throws {
        let moves = walk(count: 121, from: 2, every: 1.0 / 60, step: 10, x0: 100, y: 200)
        let plan = ZoomPlanner.plan(activity: track(clicks: [(2, 100, 200)], moves: moves))

        let segment = try #require(plan.first)
        #expect(plan.count == 1)
        #expect(segment.start == 2 && segment.end == 3.5)
        #expect(segment.focus == [.init(t: 2, x: 100, y: 200)])
    }

    @Test func aPointerThatKeepsMovingKeepsTheZoom() throws {
        var rules = ZoomRules.standard
        rules.followPointer = true
        let activity = track(clicks: [(2, 100, 100)], moves: [(2, 100, 100), (3, 300, 100), (4, 500, 100)])

        let plan = ZoomPlanner.plan(activity: activity, rules: rules)

        #expect(plan.count == 1)
        #expect(plan.first?.start == 2 && plan.first?.end == 5.5)
    }

    @Test func aRestingHandDoesNotKeepTheZoomButASlowDriftThatAddsUpDoes() throws {
        var rules = ZoomRules.standard
        rules.followPointer = true
        // Moves of 2 px each, 4 px away from the click at most: tremor.
        let tremor = track(clicks: [(2, 100, 100)], moves: [(2.5, 102, 100), (3, 100, 102), (3.2, 103, 101)])
        #expect(ZoomPlanner.plan(activity: tremor, rules: rules).first?.end == 3.5)

        // 3 px at a time: the second step is 6 px from where the last activity was, so it counts.
        let drift = track(clicks: [(2, 100, 100)], moves: [(2.3, 103, 100), (2.6, 106, 100)])
        #expect(ZoomPlanner.plan(activity: drift, rules: rules).first?.end == 2.6 + 1.5)
    }

    @Test func typingKeepsTheZoomAfterClickingIntoAField() {
        let plan = ZoomPlanner.plan(activity: track(clicks: [(2, 100, 100)], keys: [3, 4, 5]))

        #expect(plan.count == 1)
        #expect(plan.first?.start == 2 && plan.first?.end == 6.5)
    }

    @Test func aKeyAfterTheZoomEndedDoesNotBringItBack() {
        let plan = ZoomPlanner.plan(activity: track(clicks: [(2, 100, 100)], keys: [5, 6]))

        #expect(plan.count == 1 && plan[0].end == 3.5)
    }

    @Test func twoClicksCloseTogetherAreOneZoomThatStaysIn() throws {
        // The first zoom would end at 3.5; the second click comes at 4, so they join and the picture never goes back out.
        let plan = ZoomPlanner.plan(activity: track(clicks: [(2, 100, 100), (4, 1500, 800)]))

        let segment = try #require(plan.first)
        #expect(plan.count == 1)
        #expect(segment.start == 2 && segment.end == 5.5)
        #expect(segment.focus.map(\.t) == [2, 4])
    }

    @Test func zoomsLessThanTheMergeGapApartAreOneAndAtTheGapTheyAreTwo() {
        // The first ends at 3.5. A click at 5.75 leaves a gap of 2.25 s; one at 6 leaves exactly 2.5 s.
        let joined = ZoomPlanner.plan(activity: track(clicks: [(2, 100, 100), (5.75, 100, 100)]))
        let apart = ZoomPlanner.plan(activity: track(clicks: [(2, 100, 100), (6, 100, 100)]))

        #expect(joined.count == 1 && joined[0].end == 7.25)
        #expect(apart.map(\.start) == [2, 6] && apart.map(\.end) == [3.5, 7.5])
    }

    @Test func theRulesDecideTheScaleTheTimeoutAndTheMerging() {
        var rules = ZoomRules.standard
        rules.scale = 3
        rules.idleTimeout = 1
        rules.mergeGap = 0
        let plan = ZoomPlanner.plan(activity: track(clicks: [(2, 100, 100), (3.5, 100, 100)]), rules: rules)

        #expect(plan.map(\.scale) == [3, 3])
        #expect(plan.map(\.start) == [2, 3.5] && plan.map(\.end) == [3, 4.5])
    }

    @Test func theCameraFollowsThePointerAndLooksAtEveryClick() throws {
        var rules = ZoomRules.standard
        rules.followPointer = true
        // The pointer moves along a line at 60 samples a second from 2 s to 4 s, with a click at 3 s.
        let moves = walk(count: 121, from: 2, every: 1.0 / 60, step: 10, x0: 100, y: 200)
        let plan = ZoomPlanner.plan(activity: track(clicks: [(2, 100, 200), (3, 700, 200)], moves: moves), rules: rules)

        let segment = try #require(plan.first)
        let times = segment.focus.map(\.t)
        #expect(times == times.sorted())
        #expect(times.first == 2 && times.allSatisfy { $0 >= segment.start && $0 <= segment.end })
        #expect(segment.focus.contains(.init(t: 3, x: 700, y: 200)))
        // About twenty points a second, not sixty, and the click's own point is not repeated.
        #expect(segment.focus.count < 60 && segment.focus.count > 30)
        #expect(Set(times).count == times.count)
        #expect((segment.focusPoint(at: 3.5)?.x ?? 0) > 700)
    }

    @Test func aClickOutsideTheVideoDoesNotStartAZoomButCountsInsideOne() {
        let outside = track(clicks: [(2, -50, 10), (3, 5_000, 10), (4, 100, 2_000)])
        #expect(ZoomPlanner.plan(activity: outside).isEmpty)

        let inside = track(clicks: [(2, 100, 100), (3, 5_000, 10)])
        #expect(ZoomPlanner.plan(activity: inside).map(\.end) == [4.5])
    }

    @Test func aZoomNeverRunsPastTheEndOfTheRecording() {
        let activity = track(clicks: [(2, 100, 100), (9, 100, 100), (10, 100, 100), (12, 100, 100)])

        let plan = ZoomPlanner.plan(activity: activity, duration: 10)

        #expect(plan.map(\.start) == [2, 9] && plan.map(\.end) == [3.5, 10])
    }

    @Test func theOrderOfTheActivityDoesNotChangeThePlan() {
        let moves = walk(count: 40, from: 2, every: 0.25, step: 30, x0: 100, y: 100)
        let ordered = track(clicks: [(2, 100, 100), (9, 300, 300)], moves: moves, keys: [2.5, 9.5])
        var shuffled = ordered
        shuffled.pointer.reverse()
        shuffled.clicks.reverse()
        shuffled.keys.reverse()

        #expect(ZoomPlanner.plan(activity: shuffled) == ZoomPlanner.plan(activity: ordered))
    }

    @Test func aLongStretchOfActivityIsOneLongZoom() {
        let activity = track(clicks: [(1, 100, 100)], keys: (2...120).map(Double.init))

        let plan = ZoomPlanner.plan(activity: activity)

        #expect(plan.count == 1 && plan[0].start == 1 && plan[0].end == 121.5)
    }

    @Test func zoomsAreInOrderNeverOverlapAndKeepTheirDistance() {
        var generator = SystemRandomNumberGeneratorFixed(seed: 7)
        var clicks: [Spot] = [], moves: [Spot] = [], keys: [Double] = []
        var time = 0.0
        for _ in 0..<300 {
            time += generator.next(in: 0.05...3)
            switch generator.nextInt(3) {
            case 0: clicks.append((time, generator.next(in: -100...2_000), generator.next(in: -100...1_200)))
            case 1: moves.append((time, generator.next(in: 0...1_900), generator.next(in: 0...1_000)))
            default: keys.append(time)
            }
        }

        let plan = ZoomPlanner.plan(activity: track(clicks: clicks, moves: moves, keys: keys))

        #expect(!plan.isEmpty)
        #expect(plan.allSatisfy { $0.start < $0.end && !$0.focus.isEmpty })
        for (a, b) in zip(plan, plan.dropFirst()) {
            #expect(b.start - a.end >= ZoomRules.standard.mergeGap)
        }
    }

    @Test func aZoomAddedByHandLooksWhereThePointerWas() {
        let activity = track(moves: [(1, 100, 100), (4, 800, 600), (4.5, 900, 650)])

        let segment = ZoomPlanner.manualSegment(at: 5, activity: activity)

        #expect(segment.manual && segment.scale == 2)
        #expect(segment.start == 5 && segment.end == 8)
        #expect(segment.focus.first == .init(t: 5, x: 900, y: 650))
    }

    @Test func aZoomAddedByHandWithoutAnyActivityLooksAtTheMiddle() {
        let segment = ZoomPlanner.manualSegment(at: 1, duration: 2, scale: 1.5, activity: track())

        #expect(segment.scale == 1.5 && segment.end == 3)
        #expect(segment.focus == [.init(t: 1, x: 960, y: 540)])
    }

    @Test func theFocusIsJoinedByStraightLinesAndHeldBeyondItsEnds() {
        let segment = ZoomSegment(start: 0, end: 10, scale: 2, focus: [.init(t: 2, x: 0, y: 100), .init(t: 4, x: 200, y: 300)])

        #expect(segment.focusPoint(at: 0) == CGPoint(x: 0, y: 100))
        #expect(segment.focusPoint(at: 3) == CGPoint(x: 100, y: 200))
        #expect(segment.focusPoint(at: 9) == CGPoint(x: 200, y: 300))
        #expect(ZoomSegment(start: 0, end: 1, scale: 2).focusPoint(at: 0.5) == nil)
    }
}

/// The same numbers every run, so a failure can be reproduced.
struct SystemRandomNumberGeneratorFixed {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }

    mutating func nextUInt64() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(nextUInt64() % 1_000_000) / 1_000_000 * (range.upperBound - range.lowerBound)
    }

    mutating func nextInt(_ bound: Int) -> Int { Int(nextUInt64() % UInt64(bound)) }
}
