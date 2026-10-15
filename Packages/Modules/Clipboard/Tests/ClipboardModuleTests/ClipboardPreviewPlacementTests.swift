import CoreGraphics
import Testing
@testable import ClipboardModule

/// Where the large preview goes: on the display of the window it belongs to, inside that display's visible frame, taking most of it.
@Suite struct ClipboardPreviewPlacementTests {
    typealias Screen = ClipboardPanelPlacement.Screen

    /// A 1440 x 900 laptop with a menu bar of 24 and a Dock of 70 at the bottom, and a 2560 x 1440 display to its right.
    static let laptop = Screen(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 806)
    )
    static let desktop = Screen(
        frame: CGRect(x: 1440, y: -200, width: 2560, height: 1440), visibleFrame: CGRect(x: 1440, y: -200, width: 2560, height: 1416)
    )

    @Test func itTakesMostOfTheVisibleFrameOfTheHostsDisplayAndIsCentred() throws {
        let host = CGRect(x: 100, y: 300, width: 660, height: 420)
        let frame = try #require(ClipboardPreviewPlacement.frame(host: host, screens: [Self.laptop, Self.desktop]))

        #expect(frame.width == 1440 * ClipboardPreviewPlacement.share)
        #expect(frame.height == 806 * ClipboardPreviewPlacement.share)
        #expect(frame.midX == Self.laptop.visibleFrame.midX)
        #expect(frame.midY == Self.laptop.visibleFrame.midY)
        #expect(Self.laptop.visibleFrame.contains(frame))
        #expect(ClipboardPreviewPlacement.share > 0.7 && ClipboardPreviewPlacement.share < 1)
    }

    @Test func aHostOnTheOtherDisplayGetsThePreviewThere() throws {
        let host = CGRect(x: 2000, y: 100, width: 660, height: 420)
        let frame = try #require(ClipboardPreviewPlacement.frame(host: host, screens: [Self.laptop, Self.desktop]))
        #expect(Self.desktop.visibleFrame.contains(frame))
        #expect(frame.midX == Self.desktop.visibleFrame.midX)
        #expect(!Self.laptop.frame.intersects(frame))
    }

    @Test func aHostBetweenTwoDisplaysGoesWithTheOneItCoversMore() throws {
        // 100 points on the laptop, 560 on the desktop.
        let host = CGRect(x: 1340, y: 300, width: 660, height: 420)
        let frame = try #require(ClipboardPreviewPlacement.frame(host: host, screens: [Self.laptop, Self.desktop]))
        #expect(Self.desktop.visibleFrame.contains(frame))
    }

    @Test func aHostThatCoversNoDisplayAnyMoreUsesTheFirst() throws {
        let host = CGRect(x: 9000, y: 9000, width: 660, height: 420)
        let frame = try #require(ClipboardPreviewPlacement.frame(host: host, screens: [Self.laptop, Self.desktop]))
        #expect(Self.laptop.visibleFrame.contains(frame))
    }

    @Test func withoutAHostFrameItUsesTheFirstDisplay() throws {
        let frame = try #require(ClipboardPreviewPlacement.frame(host: nil, screens: [Self.laptop, Self.desktop]))
        #expect(Self.laptop.visibleFrame.contains(frame))
    }

    @Test func theMenuBarAndTheDockAreNeverCovered() throws {
        let frame = try #require(ClipboardPreviewPlacement.frame(host: Self.laptop.frame, screens: [Self.laptop]))
        #expect(frame.minY >= 70)
        #expect(frame.maxY <= 70 + 806)
    }

    @Test func noDisplayMeansNoPreview() {
        #expect(ClipboardPreviewPlacement.frame(host: nil, screens: []) == nil)
    }
}
