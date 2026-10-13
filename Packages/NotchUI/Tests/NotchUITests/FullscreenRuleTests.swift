import CoreGraphics
import Testing
@testable import NotchUI

@Suite struct FullscreenRuleTests {
    let display = CGRect(x: 0, y: 0, width: 1800, height: 1169)
    let me: pid_t = 1

    @Test func windowCoveringWholeDisplayIsFullscreen() {
        #expect(FullscreenRule.isFullscreen(windows: [WindowInfo(ownerPID: 42, layer: 0, bounds: display)], ownPID: me, displayBounds: display))
    }

    @Test func nativeFullscreenBelowCameraHousingIsFullscreen() {
        let window = WindowInfo(ownerPID: 42, layer: 0, bounds: CGRect(x: 0, y: 38, width: 1800, height: 1131))
        #expect(FullscreenRule.isFullscreen(windows: [window], ownPID: me, displayBounds: display, topInset: 38))
        #expect(!FullscreenRule.isFullscreen(windows: [window], ownPID: me, displayBounds: display))
    }

    @Test func zoomedWindowStoppingAtMenuBarIsNotFullscreen() {
        let zoomed = WindowInfo(ownerPID: 42, layer: 0, bounds: CGRect(x: 0, y: 39, width: 1800, height: 1130))
        #expect(!FullscreenRule.isFullscreen(windows: [zoomed], ownPID: me, displayBounds: display, topInset: 38))
    }

    @Test func ownWindowsAndOtherLayersDoNotCount() {
        let windows = [
            WindowInfo(ownerPID: me, layer: 0, bounds: display),
            WindowInfo(ownerPID: 42, layer: 25, bounds: display),
        ]
        #expect(!FullscreenRule.isFullscreen(windows: windows, ownPID: me, displayBounds: display))
    }

    @Test func fullscreenAppNeedNotBeFrontmostAndOnlyCoversItsDisplay() {
        let external = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        let windows = [WindowInfo(ownerPID: 7, layer: 0, bounds: external)]
        #expect(FullscreenRule.isFullscreen(windows: windows, ownPID: me, displayBounds: external))
        #expect(!FullscreenRule.isFullscreen(windows: windows, ownPID: me, displayBounds: display, topInset: 38))
    }

    @Test func wholeDisplayToleranceIsOnePoint() {
        let nearly = WindowInfo(ownerPID: 42, layer: 0, bounds: CGRect(x: 0, y: 1, width: 1800, height: 1168))
        let off = WindowInfo(ownerPID: 42, layer: 0, bounds: CGRect(x: 0, y: 2, width: 1800, height: 1167))
        #expect(FullscreenRule.isFullscreen(windows: [nearly], ownPID: me, displayBounds: display))
        #expect(!FullscreenRule.isFullscreen(windows: [off], ownPID: me, displayBounds: display))
    }
}
