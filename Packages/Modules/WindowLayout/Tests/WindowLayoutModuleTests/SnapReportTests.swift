import CoreGraphics
import Testing
@testable import WindowLayoutModule

/// The words of the notice a window that kept a size bigger than its zone gets, and when there is none.
@Suite struct SnapReportTests {
    let app = SnapApp(bundleID: "com.macpaw.CleanMyMac", name: "CleanMyMac")
    let zone = CGSize(width: 756, height: 945)

    @Test func aWindowTooWideNamesTheAppAndTheWidthItNeeds() {
        let text = SnapReport.notice(for: app, size: CGSize(width: 1040, height: 945), zone: zone)
        #expect(text == "CleanMyMac không thu nhỏ được tới ô này (tối thiểu 1040 pt)")
    }

    @Test func aWindowTooTallNamesTheHeight() {
        let text = SnapReport.notice(for: app, size: CGSize(width: 756, height: 700), zone: CGSize(width: 756, height: 473))
        #expect(text == "CleanMyMac không thu nhỏ được tới ô này (tối thiểu 700 pt chiều cao)")
    }

    @Test func aWindowTooBigEitherWayNamesBoth() {
        let text = SnapReport.notice(for: app, size: CGSize(width: 1040, height: 700), zone: CGSize(width: 756, height: 473))
        #expect(text == "CleanMyMac không thu nhỏ được tới ô này (tối thiểu 1040 × 700 pt)")
    }

    @Test func aSizeWithinTwoPointsOfTheZoneIsNotWorthSaying() {
        #expect(SnapReport.notice(for: app, size: CGSize(width: 758, height: 947), zone: zone) == nil)
        #expect(SnapReport.notice(for: app, size: CGSize(width: 700, height: 500), zone: zone) == nil, "smaller is fine")
        #expect(SnapReport.notice(for: app, size: CGSize(width: 759, height: 945), zone: zone) != nil)
    }

    @Test func theSizeIsRoundedToWholePoints() {
        #expect(SnapReport.notice(for: app, size: CGSize(width: 1039.6, height: 945), zone: zone)?.hasSuffix("(tối thiểu 1040 pt)") == true)
    }

    @Test func anAppWithoutANameIsCalledAWindow() {
        let text = SnapReport.notice(for: SnapApp(bundleID: nil, name: nil), size: CGSize(width: 1040, height: 945), zone: zone)
        #expect(text == "Cửa sổ này không thu nhỏ được tới ô này (tối thiểu 1040 pt)")
    }

    @Test func aPlacementKnowsWhenASizeIsBiggerThanItsZone() {
        let placement = SnapPlacement(
            frame: CGRect(origin: .zero, size: zone), area: CGRect(x: 0, y: 0, width: 1512, height: 945),
            anchor: SnapAnchor(horizontal: .leading, vertical: .top)
        )
        #expect(!placement.isOversize(zone))
        #expect(!placement.isOversize(CGSize(width: 758, height: 947)))
        #expect(placement.isOversize(CGSize(width: 759, height: 945)))
        #expect(placement.isOversize(CGSize(width: 756, height: 948)))
    }
}
