import CoreGraphics
import Testing
@testable import NotchUI

@Suite struct FullscreenRuleTests {
    let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func frontmostWindowCoveringDisplayIsFullscreen() {
        let windows = [WindowInfo(ownerPID: 42, layer: 0, bounds: display)]
        #expect(FullscreenRule.isFullscreen(windows: windows, frontmostPID: 42, displayBounds: display))
    }

    @Test func otherAppsOrLayersDoNotCount() {
        let windows = [
            WindowInfo(ownerPID: 7, layer: 0, bounds: display),
            WindowInfo(ownerPID: 42, layer: 25, bounds: display),
        ]
        #expect(!FullscreenRule.isFullscreen(windows: windows, frontmostPID: 42, displayBounds: display))
    }

    @Test func maximisedButNotFullscreenWindowDoesNotCount() {
        let windows = [WindowInfo(ownerPID: 42, layer: 0, bounds: CGRect(x: 0, y: 37, width: 1512, height: 945))]
        #expect(!FullscreenRule.isFullscreen(windows: windows, frontmostPID: 42, displayBounds: display))
    }
}
