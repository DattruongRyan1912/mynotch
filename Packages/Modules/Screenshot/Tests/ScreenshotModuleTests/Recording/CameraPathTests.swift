import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct CameraPathTests {
    static let frame = CGSize(width: 1920, height: 1080)

    func segment(_ start: Double, _ end: Double, scale: Double = 2, at focus: [(Double, Double, Double)] = [(0, 700, 400)]) -> ZoomSegment {
        ZoomSegment(start: start, end: end, scale: scale, focus: focus.map { .init(t: $0.0, x: $0.1, y: $0.2) })
    }

    func path(_ segments: [ZoomSegment]) -> CameraPath { CameraPath(segments: segments, frameSize: Self.frame) }

    func inside(_ rect: CGRect) -> Bool {
        rect.minX >= -1e-9 && rect.minY >= -1e-9 && rect.maxX <= Self.frame.width + 1e-9 && rect.maxY <= Self.frame.height + 1e-9
    }

    @Test func withoutZoomsTheCameraSeesTheWholePictureAlways() {
        let camera = path([])

        #expect(!camera.hasZoom)
        for time in [-5, 0, 3.3, 1_000] as [Double] {
            #expect(camera.rect(at: time) == CGRect(origin: .zero, size: Self.frame))
        }
    }

    @Test func aZoomThatHasSettledShowsTheFocusAtTheScaleWithTheVideosProportions() {
        let camera = path([segment(2, 20)])

        let rect = camera.rect(at: 10)

        #expect(abs(rect.width - 960) < 0.01 && abs(rect.height - 540) < 0.01)
        #expect(abs(rect.midX - 700) < 0.01 && abs(rect.midY - 400) < 0.01)
    }

    @Test func beforeAZoomStartsTheWholePictureShows() {
        let camera = path([segment(2, 20)])

        #expect(camera.rect(at: 1.99) == CGRect(origin: .zero, size: Self.frame))
        #expect(camera.rect(at: 2) == CGRect(origin: .zero, size: Self.frame))
    }

    @Test func theZoomIsMostOfTheWayInAfterHalfASecondAndStartsSoftly() {
        let camera = path([segment(2, 20)])

        // About 96% of the way in 0.5 s (960 px wide would be all the way), and barely moved after 50 ms.
        let after = camera.rect(at: 2.5).width
        #expect(after > 960 && after < 1_010)
        #expect(camera.rect(at: 2.05).width > 1_800)
    }

    @Test func theZoomIsBackOutWithinAboutHalfASecondAfterTheEndAndThenExactlyWhole() {
        let camera = path([segment(2, 6)])

        #expect(camera.rect(at: 6.6).width > 0.97 * 1920)
        #expect(camera.rect(at: 6.6).width < 1920)
        #expect(camera.rect(at: 9) == CGRect(origin: .zero, size: Self.frame))
        #expect(camera.rect(at: 100) == CGRect(origin: .zero, size: Self.frame))
    }

    @Test func theCameraStaysFlushWithAnEdgeWhenTheFocusIsAtTheEdgeOrBeyond() {
        let corner = path([segment(1, 20, at: [(0, 1_915, 1_075)])]).rect(at: 10)
        #expect(abs(corner.maxX - 1_920) < 0.01 && abs(corner.maxY - 1_080) < 0.01)

        let beyond = path([segment(1, 20, at: [(0, -400, 5_000)])]).rect(at: 10)
        #expect(abs(beyond.minX) < 0.01 && abs(beyond.maxY - 1_080) < 0.01)
    }

    @Test func aBiggerScaleShowsLess() {
        #expect(abs(path([segment(1, 20, scale: 3)]).rect(at: 10).width - 640) < 0.01)
        #expect(abs(path([segment(1, 20, scale: 1.25)]).rect(at: 10).width - 1_536) < 0.01)
    }

    @Test func aScaleOfOneOrLessDoesNothing() {
        let camera = path([segment(1, 20, scale: 1), segment(30, 40, scale: 0.5)])

        #expect(!camera.hasZoom)
        #expect(camera.rect(at: 10) == CGRect(origin: .zero, size: Self.frame))
    }

    @Test func theCameraFollowsAPointerThatMovesWhileZoomedIn() {
        let camera = path([segment(1, 20, at: [(1, 500, 300), (6, 500, 300), (8, 1_400, 800)])])

        let before = camera.rect(at: 6)
        let after = camera.rect(at: 12)

        #expect(abs(before.midX - 500) < 0.5 && abs(before.midY - 300) < 0.5)
        #expect(abs(after.midX - 1_400) < 0.5 && abs(after.midY - 800) < 0.5)
        // In between it is on its way, not there yet.
        let moving = camera.rect(at: 7.5)
        #expect(moving.midX > before.midX && moving.midX < after.midX)
    }

    @Test func theViewNeverLeavesThePictureWhateverTheFocusDoes() {
        var wild: [(Double, Double, Double)] = []
        for index in 0..<200 {
            let x = Double((index * 977) % 4_000) - 1_000
            let y = Double((index * 613) % 3_000) - 900
            wild.append((Double(index) * 0.05, x, y))
        }
        let camera = path([segment(0.5, 9, at: wild), segment(10, 12, scale: 3, at: [(10, -50, -50)]), segment(11, 14, scale: 1.5, at: [(11, 9_000, 9_000)])])

        var time = -1.0
        while time < 20 {
            let rect = camera.rect(at: time)
            #expect(inside(rect), "at \(time): \(rect)")
            #expect(rect.width.isFinite && rect.height.isFinite && rect.minX.isFinite && rect.minY.isFinite)
            #expect(abs(rect.width / rect.height - 16.0 / 9) < 1e-9)
            time += 1.0 / 240
        }
    }

    /// A spring that was heading for the edge when its target moved away carries on a little past it; the view is moved back
    /// inside, never allowed out. Zooms of all sizes with focus jumping between the corners, the edges and beyond.
    @Test func theViewStaysInsideWhenTargetsReverseJustAsTheViewReachesAnEdge() {
        var random = SystemRandomNumberGeneratorFixed(seed: 11)
        let places: [Double] = [-500, 0, 0, 960, 1_920, 1_920, 2_400]
        let scales: [Double] = [1.25, 2, 3]
        var worst = 0.0
        for _ in 0..<300 {
            var segments: [ZoomSegment] = []
            for _ in 0..<(1 + random.nextInt(3)) {
                let start = random.next(in: 0...5)
                let end = start + random.next(in: 0.2...3)
                var focus: [ZoomSegment.Focus] = []
                var time = start
                while time < end {
                    focus.append(.init(t: time, x: places[random.nextInt(places.count)], y: places[random.nextInt(places.count)] * 0.5625))
                    time += random.next(in: 0.02...0.4)
                }
                segments.append(ZoomSegment(start: start, end: end, scale: scales[random.nextInt(3)], focus: focus))
            }
            let camera = path(segments)
            var time = 0.0
            while time < 12 {
                let rect = camera.rect(at: time)
                worst = max(worst, -rect.minX, -rect.minY, rect.maxX - Self.frame.width, rect.maxY - Self.frame.height)
                time += 1.0 / 120
            }
        }
        #expect(worst < 1e-9, "the view went \(worst) px outside the picture")
    }

    /// The camera under a click every 100 ms at opposite corners, with typing between: the picture must not jump.
    @Test func theViewMovesSmoothlyUnderClicksAtOppositeCornersEveryTenthOfASecond() {
        var focus: [ZoomSegment.Focus] = []
        for index in 0..<60 {
            let left = index.isMultiple(of: 2)
            focus.append(.init(t: 1 + Double(index) * 0.1, x: left ? 60 : 1_860, y: left ? 40 : 1_040))
        }
        let camera = path([ZoomSegment(start: 1, end: 8, scale: 2, focus: focus)])

        var worst = 0.0
        var previous = camera.rect(at: 0)
        var time = 1.0 / 60
        while time < 12 {
            let rect = camera.rect(at: time)
            worst = max(worst, abs(rect.minX - previous.minX) / 1_920, abs(rect.maxX - previous.maxX) / 1_920)
            worst = max(worst, abs(rect.minY - previous.minY) / 1_080, abs(rect.maxY - previous.maxY) / 1_080)
            previous = rect
            time += 1.0 / 60
        }

        // A jump would be a large part of the picture in one frame; the spring moves at most a few percent.
        #expect(worst < 0.04, "the biggest step in one frame was \(worst * 100)% of the picture")
        #expect(worst > 0.005, "the test did not move the camera")
    }

    @Test func theViewMovesSmoothlyWhenSegmentsFollowEachOtherAndWhenOneStartsMidWayOut() {
        // The second zoom starts 0.2 s into the first one's way out, from wherever the picture is by then.
        let camera = path([segment(0, 4, at: [(0, 400, 300)]), segment(4.2, 8, at: [(4.2, 1_500, 800)])])

        var previous = camera.rect(at: 0)
        var time = 1.0 / 60
        var worst = 0.0
        while time < 14 {
            let rect = camera.rect(at: time)
            worst = max(worst, abs(rect.minX - previous.minX) / 1_920, abs(rect.maxX - previous.maxX) / 1_920)
            previous = rect
            time += 1.0 / 60
        }
        let meeting = camera.rect(at: 4.2)

        #expect(worst < 0.04, "the biggest step in one frame was \(worst * 100)% of the picture")
        // It did not go all the way out and back in: it is between the two sizes.
        #expect(meeting.width > 1_100 && meeting.width < 1_800)
        #expect(abs(camera.rect(at: 4.2 + 0.0005).width - camera.rect(at: 4.2 - 0.0005).width) < 5)
    }

    @Test func theSamePathIsReadWhateverTheOrderOfTheQuestions() {
        let camera = path([segment(1, 5), segment(20, 23, at: [(20, 1_700, 100)])])
        let times: [Double] = Array(stride(from: 0.0, to: 30.0, by: 0.0173))

        let forwards = times.map { camera.rect(at: $0) }
        let backwards = times.reversed().map { camera.rect(at: $0) }.reversed()

        #expect(forwards == Array(backwards))
        // Two zooms far apart each start from the whole picture.
        #expect(camera.rect(at: 20) == CGRect(origin: .zero, size: Self.frame))
        #expect(camera.rect(at: 15) == CGRect(origin: .zero, size: Self.frame))
    }

    @Test func zoomsDraggedOverEachOtherLeaveTheLaterOneInCharge() {
        let camera = path([segment(1, 10, at: [(1, 300, 300)]), segment(4, 6, at: [(4, 1_500, 800)]), segment(0, 2, scale: 3, at: [(0, 100, 100)])])

        var time = 0.0
        while time < 15 {
            #expect(inside(camera.rect(at: time)))
            time += 0.01
        }
        // Between 4 and 6 the later one looks at the lower right; at 9.9 the first is back in charge.
        #expect(camera.rect(at: 5.9).midX > 1_000)
        #expect(camera.rect(at: 9.9).midX < 600)
    }

    @Test func aTimeThatIsNotANumberShowsTheWholePicture() {
        let camera = path([segment(1, 5)])

        #expect(camera.rect(at: .nan) == CGRect(origin: .zero, size: Self.frame))
        #expect(camera.rect(at: .infinity) == CGRect(origin: .zero, size: Self.frame))
    }
}
