import CoreGraphics
import NotchUI
import Testing
@testable import LockScreenModule

@Suite struct LockScreenPanelTests {
    private var size: CGSize { LockScreenPanel.size }
    private var gap: CGFloat { LockScreenPanel.gap }

    @Test func sitsCentredUnderAHardwareNotch() {
        let screen = ScreenDescriptor(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
            auxiliaryTopLeftWidth: 656, auxiliaryTopRightWidth: 656, menuBarHeight: 32
        )
        let frame = LockScreenPanel.frame(on: screen)
        #expect(frame.size == size)
        #expect(frame.midX == 756)
        #expect(frame.maxY == 982 - 32 - gap)
    }

    @Test func followsAnAsymmetricNotch() {
        let screen = ScreenDescriptor(
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800), safeAreaTop: 30,
            auxiliaryTopLeftWidth: 400, auxiliaryTopRightWidth: 500, menuBarHeight: 30
        )
        // The notch is 100 wide and its centre is 450 from the left edge, 50 left of the screen centre.
        #expect(LockScreenPanel.frame(on: screen).midX == 450)
    }

    @Test func usesTheMenuBarHeightWhereThereIsNoNotch() {
        let screen = ScreenDescriptor(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeAreaTop: 0,
            auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil, menuBarHeight: 24
        )
        let frame = LockScreenPanel.frame(on: screen)
        #expect(frame.midX == 960)
        #expect(frame.maxY == 1080 - 24 - gap)
    }

    @Test func staysOnAScreenWhoseOriginIsNotZero() {
        let screen = ScreenDescriptor(
            frame: CGRect(x: 1512, y: -200, width: 1920, height: 1080), safeAreaTop: 0,
            auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil, menuBarHeight: 24
        )
        let frame = LockScreenPanel.frame(on: screen)
        let centre: CGFloat = 2472
        let top: CGFloat = 856 - gap
        #expect(frame.midX == centre)
        #expect(frame.maxY == top)
    }
}
