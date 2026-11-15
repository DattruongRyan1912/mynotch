import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotModule

@Suite struct ClickEffectTests {
    let frame = CGSize(width: 1920, height: 1080)

    func effect(_ times: [Double], at x: Double = 300, _ y: Double = 200) -> ClickEffect {
        ClickEffect(clicks: times.map { .init(t: $0, x: x, y: y, button: .left) }, frameSize: frame)
    }

    @Test func aRingShowsAtTheClickAndNotBeforeOrAfter() {
        let clicks = effect([2])

        #expect(clicks.rings(at: 1.99).isEmpty)
        #expect(clicks.rings(at: 2).count == 1)
        #expect(clicks.rings(at: 2.49).count == 1)
        #expect(clicks.rings(at: 2.5).isEmpty)
        #expect(clicks.rings(at: 30).isEmpty)
    }

    @Test func aRingIsWhereTheClickWasAndGrowsAndFadesWhileItLasts() throws {
        let clicks = effect([2], at: 700, 400)

        let start = try #require(clicks.rings(at: 2).first)
        let middle = try #require(clicks.rings(at: 2.25).first)
        let end = try #require(clicks.rings(at: 2.49).first)

        #expect(start.x == 700 && start.y == 400 && end.x == 700 && end.y == 400)
        #expect(start.opacity == 1 && middle.opacity < start.opacity && end.opacity < middle.opacity && end.opacity < 0.1)
        #expect(start.radius < middle.radius && middle.radius < end.radius)
    }

    @Test func severalClicksShowTogetherWhileTheirRingsOverlap() {
        let clicks = effect([2, 2.2, 2.4, 5])

        #expect(clicks.rings(at: 2.45).count == 3)
        #expect(clicks.rings(at: 2.65).count == 2)
        #expect(clicks.rings(at: 5.1).count == 1)
    }

    @Test func clicksBeforeTheStartOfWhatIsPlayingAreLeftOut() {
        let clicks = effect([2])

        // The video was cut so that what plays began at 2.2: the click that made this ring is not in it.
        #expect(clicks.rings(at: 2.3, notBefore: 2.2).isEmpty)
        #expect(clicks.rings(at: 2.3, notBefore: 2).count == 1)
    }

    @Test func clicksGivenOutOfOrderAreFoundAllTheSame() {
        let clicks = ClickEffect(clicks: [4, 1, 3, 2].map { .init(t: $0, x: Double($0), y: 0, button: .right) }, frameSize: frame)

        #expect(clicks.rings(at: 3.25).map(\.x) == [3])
        #expect(clicks.rings(at: 1.25).map(\.x) == [1])
    }

    @Test func theRingIsSizedByTheShorterSideOfTheVideo() throws {
        let small = ClickEffect(clicks: [.init(t: 0, x: 0, y: 0, button: .left)], frameSize: CGSize(width: 1280, height: 720))
        let large = ClickEffect(clicks: [.init(t: 0, x: 0, y: 0, button: .left)], frameSize: CGSize(width: 5120, height: 2880))

        let ratio = try #require(large.rings(at: 0).first).radius / #require(small.rings(at: 0).first).radius

        #expect(abs(ratio - 4) < 1e-9)
    }
}
