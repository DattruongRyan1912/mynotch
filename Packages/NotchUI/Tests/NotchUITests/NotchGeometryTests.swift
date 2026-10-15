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

    // MARK: the size the user chooses

    @Test func theOpenWidthFollowsTheSettingFrom480To900() {
        for (width, expected) in [(CGFloat(480), CGFloat(480)), (600, 600), (720, 720), (800, 800), (900, 900)] {
            let geometry = NotchGeometry(screen: Self.macBook14, config: NotchLayoutConfig(openWidth: width))
            #expect(geometry.shapeSize(for: .open(nil)).width == expected, "\(width)")
            #expect(geometry.shapeSize(for: .toast).width == expected, "\(width)")
            #expect(geometry.openWidth == expected)
        }
    }

    @Test func anOpenWidthOutsideTheRangeIsHeldToIt() {
        for (width, expected) in [(CGFloat(0), CGFloat(480)), (479, 480), (901, 900), (5000, 900), (.infinity, 900)] {
            let geometry = NotchGeometry(screen: Self.macBook14, config: NotchLayoutConfig(openWidth: width))
            #expect(geometry.shapeSize(for: .open(nil)).width == expected, "\(width)")
        }
    }

    @Test func theOpenNotchNeverGetsWiderThanTheScreen() {
        func narrow(_ width: CGFloat) -> ScreenDescriptor {
            ScreenDescriptor(
                frame: CGRect(x: 0, y: 0, width: width, height: 600),
                safeAreaTop: 0, auxiliaryTopLeftWidth: nil, auxiliaryTopRightWidth: nil, menuBarHeight: 24
            )
        }
        let config = NotchLayoutConfig(openWidth: 900)
        #expect(NotchGeometry(screen: narrow(800), config: config).shapeSize(for: .open(nil)).width == 800)
        #expect(NotchGeometry(screen: narrow(1024), config: config).shapeSize(for: .open(nil)).width == 900)
        // Narrower than the narrowest notch: the narrowest, as before.
        #expect(NotchGeometry(screen: narrow(300), config: config).shapeSize(for: .open(nil)).width == 480)
        // Only the open notch is held to the screen; the setting itself is not touched.
        #expect(config.openWidth == 900)
    }

    @Test func theMaxHeightCapsTheContentAndTheNotchIsAsTallAsItsContentUpToThat() {
        let notch: CGFloat = 32
        for (limit, content, expected) in [
            (CGFloat(300), CGFloat(190), CGFloat(190)), (300, 450, 300), (200, 190, 190), (200, 230, 200), (200, 300, 200),
            (400, 300, 300), (400, 350, 350), (400, 900, 400), (350, 120, 120), (400, 50, 120),
        ] {
            let geometry = NotchGeometry(screen: Self.macBook14, config: NotchLayoutConfig(maxContentHeight: limit))
            for state in [NotchState.open(nil), .toast] {
                #expect(geometry.shapeSize(for: state, contentHeight: content).height == notch + expected, "\(limit) \(content) \(state)")
            }
        }
    }

    @Test func aMaxHeightOutsideTheRangeIsHeldTo200Through400() {
        for (limit, expected) in [(CGFloat(0), CGFloat(200)), (199, 200), (401, 400), (.infinity, 400), (-50, 200)] {
            let geometry = NotchGeometry(screen: Self.macBook14, config: NotchLayoutConfig(maxContentHeight: limit))
            #expect(geometry.maxContentHeight == expected, "\(limit)")
            #expect(geometry.shapeSize(for: .open(nil), contentHeight: 10_000).height == 32 + expected, "\(limit)")
        }
    }

    @Test func theDefaultsAreWhatTheNotchHasAlwaysBeen() {
        let geometry = NotchGeometry(screen: Self.macBook14, config: NotchLayoutConfig())
        #expect(geometry.openWidth == 600)
        #expect(geometry.maxContentHeight == 300)
        #expect(NotchLayoutConfig().openWidth == 600)
        #expect(NotchLayoutConfig().maxContentHeight == NotchTab.heightRange.upperBound)
    }

    @Test func theHitAreaOfAWiderTallerOpenNotchGrowsWithIt() {
        let geometry = NotchGeometry(screen: Self.macBook14, config: NotchLayoutConfig(openWidth: 900, maxContentHeight: 400))
        let rect = geometry.hitRect(for: .open(nil), contentHeight: 380, in: Self.macBook14.frame)
        #expect(rect == CGRect(x: 754.5 - 450 - 8, y: 982 - (32 + 380) - 8, width: 900 + 16, height: 32 + 380 + 8 + 1))
        let drag = geometry.dragHitRect(for: .open(nil), contentHeight: 380, in: Self.macBook14.frame)
        #expect(drag == CGRect(x: 754.5 - 450 - 40, y: 982 - (32 + 380) - 40, width: 900 + 80, height: 32 + 380 + 40 + 1))
        // The shape never passes the fixed panel's edges.
        #expect(geometry.panelFrame(in: Self.macBook14.frame).contains(CGRect(x: 754.5 - 450, y: 982 - 412, width: 900, height: 412)))
    }

    @Test func panelIsTopCentredAndMaxSized() {
        let geometry = NotchGeometry(screen: Self.external, config: NotchLayoutConfig())
        let frame = geometry.panelFrame(in: Self.external.frame)
        // As wide as the widest open notch and as tall as the notch plus the tallest content the settings allow.
        #expect(frame == CGRect(x: 1512 + 960 - 450, y: 1080 - 425, width: 900, height: 425))
    }

    @Test func thePanelDoesNotChangeWithTheSizeSettings() {
        let small = NotchGeometry(screen: Self.external, config: NotchLayoutConfig(openWidth: 480, maxContentHeight: 200))
        let large = NotchGeometry(screen: Self.external, config: NotchLayoutConfig(openWidth: 900, maxContentHeight: 400))
        #expect(small.panelFrame(in: Self.external.frame) == large.panelFrame(in: Self.external.frame))
        #expect(small.panelSize == CGSize(width: 900, height: 25 + 400))
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

    @Test func dragHitRectFollowsTheOpenAndCompactShapes() {
        let geometry = NotchGeometry(screen: Self.macBook14, config: NotchLayoutConfig())
        let frame = Self.macBook14.frame
        #expect(geometry.dragHitRect(for: .open(nil), contentHeight: 190, in: frame)
            == CGRect(x: 754.5 - 300 - 40, y: 982 - 222 - 40, width: 600 + 80, height: 222 + 40 + 1))
        #expect(geometry.dragHitRect(for: .compact, in: frame)
            == CGRect(x: 754.5 - 162.5 - 40, y: 982 - 32 - 40, width: 325 + 80, height: 32 + 40 + 1))
    }

    @Test func secondaryScreenWithOffsetOriginUsesItsOwnTopCentre() {
        let geometry = NotchGeometry(screen: Self.externalAboveLeft, config: NotchLayoutConfig())
        #expect(geometry.panelFrame(in: Self.externalAboveLeft.frame) == CGRect(x: -490, y: 2062 - 425, width: 900, height: 425))
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

    @Test func layoutConfigReadsTheOpenSizeSettings() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        #expect(NotchLayoutConfig(settings: settings).openWidth == 600)
        #expect(NotchLayoutConfig(settings: settings).maxContentHeight == 300)
        settings.set(850, for: InterfaceSettings.openWidth)
        settings.set(380, for: InterfaceSettings.maxOpenHeight)
        #expect(NotchLayoutConfig(settings: settings).openWidth == 850)
        #expect(NotchLayoutConfig(settings: settings).maxContentHeight == 380)
    }

    @Test func layoutConfigReadsVirtualHeightSetting() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        #expect(NotchLayoutConfig(settings: settings).virtualNotchHeight == nil)
        settings.set(false, for: InterfaceSettings.virtualNotchMatchesMenuBar)
        settings.set(10, for: InterfaceSettings.virtualNotchHeight)
        #expect(NotchLayoutConfig(settings: settings).virtualNotchHeight == 24)
    }

    /// Every shape the notch can take, as the rect it covers when anchored to the top centre of `screenFrame`.
    func allShapeRects(_ geometry: NotchGeometry, in screenFrame: CGRect) -> [(NotchState, CGFloat, CGRect)] {
        var rects: [(NotchState, CGFloat, CGRect)] = []
        for height in stride(from: NotchTab.heightRange.lowerBound, through: NotchGeometry.contentHeightLimits.upperBound + 10, by: 10) {
            for state in [NotchState.closed, .compact, .open("a"), .open(nil), .toast] {
                let size = geometry.shapeSize(for: state, contentHeight: height)
                rects.append((state, height, CGRect(
                    x: screenFrame.midX + geometry.centerOffset - size.width / 2, y: screenFrame.maxY - size.height,
                    width: size.width, height: size.height
                )))
            }
        }
        return rects
    }

    @Test func theFixedPanelCoversEveryShapeSoNoTabSwitchOrResizeNeedsAWindowFrameChange() {
        let screens = [Self.macBook14, Self.external, Self.externalAboveLeft]
        let configs = [
            NotchLayoutConfig(),
            NotchLayoutConfig(virtualNotchWidth: 300, virtualNotchHeight: 40, openWidth: 720),
            NotchLayoutConfig(virtualNotchWidth: 120, virtualNotchHeight: 24, openWidth: 480, maxContentHeight: 200),
            NotchLayoutConfig(virtualNotchWidth: 300, virtualNotchHeight: 40, openWidth: 900, maxContentHeight: 400),
            // Past the ends of both ranges: held to them.
            NotchLayoutConfig(virtualNotchWidth: 300, virtualNotchHeight: 40, openWidth: 5000, maxContentHeight: 5000),
        ]
        for screen in screens {
            for config in configs {
                let geometry = NotchGeometry(screen: screen, config: config)
                let panel = geometry.panelFrame(in: screen.frame)
                for (state, height, rect) in allShapeRects(geometry, in: screen.frame) {
                    #expect(rect.width > 0 && rect.height > 0, "\(state) \(height) is never zero-sized")
                    #expect(panel.contains(rect), "\(state) \(height) fits the fixed panel")
                }
            }
        }
    }

    @Test func switchingTabsChangesOnlyTheHeightOfTheSameOpenShape() {
        let geometry = NotchGeometry(screen: Self.macBook14, config: NotchLayoutConfig())
        let short = geometry.shapeSize(for: .open("a"), contentHeight: 130)
        let tall = geometry.shapeSize(for: .open("b"), contentHeight: 230)
        #expect(short.width == tall.width)
        #expect(tall.height - short.height == 100)
        #expect(geometry.cornerRadii(for: .open("a")) == geometry.cornerRadii(for: .open("b")))
        #expect(geometry.cornerRadii(for: .open("a")) == geometry.cornerRadii(for: .toast))
    }
}
