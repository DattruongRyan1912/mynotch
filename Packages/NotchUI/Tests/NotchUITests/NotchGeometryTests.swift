import CoreGraphics
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import NotchUI

@Suite struct NotchGeometryTests {
    static let macBook14 = ScreenDescriptor(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaTop: 32, auxiliaryTopLeftWidth: 662, auxiliaryTopRightWidth: 665, menuBarHeight: 37
    )
    static let external = ScreenDescriptor(
        frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
        safeAreaTop: 0, auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil, menuBarHeight: 25
    )
    static let externalAboveLeft = ScreenDescriptor(
        frame: CGRect(x: -1000, y: 982, width: 1920, height: 1080),
        safeAreaTop: 0, auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil, menuBarHeight: 25
    )

    @Test func hardwareNotchUsesAuxiliaryAreas() {
        let geometry = NotchGeometry(screen: Self.macBook14, config: NotchLayoutConfig())
        #expect(geometry.kind == .hardware)
        #expect(geometry.notchSize == CGSize(width: 185, height: 32))
        #expect(geometry.centerOffset == -1.5)
    }

    @Test func virtualNotchFallsBackToMenuBarHeight() {
        let geometry = NotchGeometry(screen: Self.external, config: NotchLayoutConfig())
        #expect(geometry.kind == .virtual)
        #expect(geometry.notchSize == CGSize(width: 185, height: 25))
    }

    @Test func virtualNotchClampsConfiguredSize() {
        let config = NotchLayoutConfig(virtualNotchWidth: 999, virtualNotchHeight: 10)
        let geometry = NotchGeometry(screen: Self.external, config: config)
        #expect(geometry.notchSize == CGSize(width: 300, height: 24))
    }

    @Test func shapeSizesPerState() {
        let geometry = NotchGeometry(screen: Self.macBook14, config: NotchLayoutConfig())
        #expect(geometry.shapeSize(for: .closed) == CGSize(width: 197, height: 32))
        #expect(geometry.shapeSize(for: .compact) == CGSize(width: 325, height: 32))
        #expect(geometry.shapeSize(for: .open(nil), contentHeight: 190) == CGSize(width: 600, height: 222))
        #expect(geometry.shapeSize(for: .open(nil), contentHeight: 900) == CGSize(width: 600, height: 332))
    }

    @Test func panelIsTopCentredAndMaxSized() {
        let geometry = NotchGeometry(screen: Self.external, config: NotchLayoutConfig())
        let frame = geometry.panelFrame(in: Self.external.frame)
        #expect(frame == CGRect(x: 1512 + 960 - 360, y: 1080 - 325, width: 720, height: 325))
    }

    @Test func hitRectIsShapePlusPadding() {
        let geometry = NotchGeometry(screen: Self.macBook14, config: NotchLayoutConfig())
        let rect = geometry.hitRect(for: .closed, in: Self.macBook14.frame)
        #expect(rect == CGRect(x: 756 - 1.5 - 98.5 - 8, y: 982 - 32 - 8, width: 197 + 16, height: 32 + 8 + 1))
    }

    @Test func dragHitRectGrowsFortyPointsOnEachSideAndBelow() {
        let geometry = NotchGeometry(screen: Self.macBook14, config: NotchLayoutConfig())
        let rect = geometry.dragHitRect(for: .closed, in: Self.macBook14.frame)
        #expect(rect == CGRect(x: 754.5 - 98.5 - 40, y: 982 - 32 - 40, width: 197 + 80, height: 32 + 40 + 1))
        #expect(rect.contains(CGPoint(x: 754.5, y: 982)))
        #expect(!rect.contains(CGPoint(x: 754.5, y: 983)))
    }

    @Test func secondaryScreenWithOffsetOriginUsesItsOwnTopCentre() {
        let geometry = NotchGeometry(screen: Self.externalAboveLeft, config: NotchLayoutConfig())
        #expect(geometry.panelFrame(in: Self.externalAboveLeft.frame) == CGRect(x: -400, y: 2062 - 325, width: 720, height: 325))
        #expect(geometry.hitRect(for: .compact, in: Self.externalAboveLeft.frame)
            == CGRect(x: -40 - 162.5 - 8, y: 2062 - 25 - 8, width: 325 + 16, height: 25 + 8 + 1))
    }

    @Test func hitRectIncludesTopRowButNotTheDisplayAbove() {
        let geometry = NotchGeometry(screen: Self.macBook14, config: NotchLayoutConfig())
        let rect = geometry.hitRect(for: .closed, in: Self.macBook14.frame)
        #expect(rect.contains(CGPoint(x: 754.5, y: 982)))
        #expect(!rect.contains(CGPoint(x: 754.5, y: 983)))
    }

    @Test func mouseLocationMembershipIncludesTopEdgeOnly() {
        let frame = Self.macBook14.frame
        #expect(frame.containsMouseLocation(CGPoint(x: 10, y: 982)))
        #expect(!frame.containsMouseLocation(CGPoint(x: 10, y: 983)))
        #expect(!frame.containsMouseLocation(CGPoint(x: 10, y: 0)))
        #expect(Self.externalAboveLeft.frame.containsMouseLocation(CGPoint(x: 10, y: 983)))
    }

    @Test func invalidAuxiliaryAreasFallBackToVirtualNotch() {
        let bogus = ScreenDescriptor(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                     safeAreaTop: 32, auxiliaryTopLeftWidth: 1000, auxiliaryTopRightWidth: 1000, menuBarHeight: 37)
        #expect(NotchGeometry(screen: bogus, config: NotchLayoutConfig()).kind == .virtual)
    }

    @Test func layoutConfigReadsVirtualHeightSetting() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        #expect(NotchLayoutConfig(settings: settings).virtualNotchHeight == nil)
        settings.set(false, for: InterfaceSettings.virtualNotchMatchesMenuBar)
        settings.set(10, for: InterfaceSettings.virtualNotchHeight)
        #expect(NotchLayoutConfig(settings: settings).virtualNotchHeight == 24)
    }
}
