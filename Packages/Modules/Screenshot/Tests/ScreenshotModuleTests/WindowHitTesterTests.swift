import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct WindowHitTesterTests {
    static let me: pid_t = 99

    static func window(_ id: CGWindowID, pid: pid_t = 42, layer: Int = 0, bounds: CGRect) -> CapturableWindow {
        CapturableWindow(id: id, ownerPID: pid, layer: layer, bounds: bounds, ownerName: nil, title: nil)
    }

    @Test func picksFrontmostWindowContainingPoint() {
        let windows = [
            Self.window(1, bounds: CGRect(x: 500, y: 500, width: 100, height: 100)),
            Self.window(2, bounds: CGRect(x: 0, y: 0, width: 400, height: 400)),
            Self.window(3, bounds: CGRect(x: 0, y: 0, width: 800, height: 800)),
        ]
        #expect(WindowHitTester.window(at: CGPoint(x: 50, y: 50), in: windows, excludingPID: Self.me)?.id == 2)
        #expect(WindowHitTester.window(at: CGPoint(x: 550, y: 550), in: windows, excludingPID: Self.me)?.id == 1)
        #expect(WindowHitTester.window(at: CGPoint(x: 700, y: 50), in: windows, excludingPID: Self.me)?.id == 3)
    }

    @Test func skipsOtherLayersOwnWindowsAndTinyWindows() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        let windows = [
            Self.window(1, layer: 25, bounds: bounds),
            Self.window(2, pid: Self.me, bounds: bounds),
            Self.window(3, bounds: CGRect(x: 0, y: 0, width: 19, height: 400)),
            Self.window(4, bounds: CGRect(x: 0, y: 0, width: 400, height: 19)),
            Self.window(5, bounds: bounds),
        ]
        #expect(WindowHitTester.window(at: CGPoint(x: 10, y: 10), in: windows, excludingPID: Self.me)?.id == 5)
    }

    @Test func minimumSizeIsInclusiveAndConfigurable() {
        let windows = [Self.window(1, bounds: CGRect(x: 0, y: 0, width: 20, height: 20))]
        #expect(WindowHitTester.window(at: CGPoint(x: 5, y: 5), in: windows, excludingPID: Self.me)?.id == 1)
        #expect(WindowHitTester.window(at: CGPoint(x: 5, y: 5), in: windows, excludingPID: Self.me, minimumSize: 21) == nil)
    }

    @Test func returnsNilWhenNoWindowContainsPoint() {
        let windows = [Self.window(1, bounds: CGRect(x: 0, y: 0, width: 400, height: 400))]
        #expect(WindowHitTester.window(at: CGPoint(x: 400, y: 10), in: windows, excludingPID: Self.me) == nil)
        #expect(WindowHitTester.window(at: CGPoint(x: -1, y: 10), in: windows, excludingPID: Self.me) == nil)
        #expect(WindowHitTester.window(at: CGPoint(x: 10, y: 10), in: [], excludingPID: Self.me) == nil)
    }
}
