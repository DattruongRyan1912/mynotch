import CoreGraphics
import Testing
@testable import ScreenshotModule

/// Where the chip goes: in a corner of the screen the user is on, never in the notch's hover area.
@Suite struct CaptureChipGeometryTests {
    let size = CGSize(width: 220, height: 64)
    /// A 1440×900 main screen whose menu bar takes the top 38 points, and a 1920×1080 one to its right.
    let main = ChipScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 862))
    let side = ChipScreen(frame: CGRect(x: 1440, y: -180, width: 1920, height: 1080), visibleFrame: CGRect(x: 1440, y: -180, width: 1920, height: 1055))

    @Test func theChipSitsInTheTopRightCornerBelowTheMenuBar() {
        let frame = CaptureChipGeometry.frame(size: size, pointer: CGPoint(x: 500, y: 400), screens: [main, side])
        #expect(frame == CGRect(x: 1440 - 16 - 220, y: 862 - 16 - 64, width: 220, height: 64))
    }

    @Test func itFollowsThePointerToTheOtherScreen() {
        let frame = CaptureChipGeometry.frame(size: size, pointer: CGPoint(x: 2000, y: 100), screens: [main, side])
        #expect(frame == CGRect(x: 3360 - 16 - 220, y: 875 - 16 - 64, width: 220, height: 64))
    }

    @Test func aPointerOnNoScreenGetsTheMainOne() {
        let frame = CaptureChipGeometry.frame(size: size, pointer: CGPoint(x: -500, y: -500), screens: [main, side])
        #expect(frame.maxX == 1424)
    }

    @Test func theChipIsNeverOutsideAScreenSmallerThanIt() {
        let tiny = ChipScreen(frame: CGRect(x: 0, y: 0, width: 100, height: 40), visibleFrame: CGRect(x: 0, y: 0, width: 100, height: 40))
        let frame = CaptureChipGeometry.frame(size: size, pointer: .zero, screens: [tiny])
        #expect(frame.minX == 0 && frame.minY == 0)
    }

    @Test func withNoScreensItIsWhereTheOriginIs() {
        #expect(CaptureChipGeometry.frame(size: size, pointer: .zero, screens: []) == CGRect(origin: .zero, size: size))
    }
}
