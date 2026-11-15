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
        #expect(geometry.shapeSize(for: .open(nil), contentHeight: 900) == CGSize(width: 600, height: 272))
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

    @Test func theDefaultsAreWhatTheNotchHasAlwaysBeen() {
        let geometry = NotchGeometry(screen: Self.macBook14, config: NotchLayoutConfig())
        #expect(geometry.openWidth == 600)
        #expect(NotchLayoutConfig().openWidth == 600)
    }

    // MARK: no tab is cut

    @Test func theTallestContentIsTheMostATabMayAsk() {
        // The tallest ask of the tabs there are is Clipboard's 230 pt; 240 leaves a little room.
        #expect(NotchGeometry.maxContentHeight == NotchTab.heightRange.upperBound)
        #expect(NotchGeometry.maxContentHeight == 240)
        #expect(NotchTab.heightRange.upperBound >= 230 + 10)
    }

    @Test func aTabThatAsksForWhatATabMayIsNeverCut() {
        let notch: CGFloat = 32
        let geometry = NotchGeometry(screen: Self.macBook14, config: NotchLayoutConfig())
        var cut: [String] = []
        for ask in stride(from: NotchTab.heightRange.lowerBound, through: NotchTab.heightRange.upperBound, by: 1) {
            for state in [NotchState.open("a"), .toast] where geometry.shapeSize(for: state, contentHeight: ask).height != notch + ask {
                cut.append("ask \(ask) \(state)")
            }
        }
        #expect(cut.isEmpty, "\(cut.prefix(5))")
    }

    @Test func theNotchIsAsTallAsItsContentFrom120To240AndNoTaller() {
        let geometry = NotchGeometry(screen: Self.macBook14, config: NotchLayoutConfig())
        for (content, expected) in [(CGFloat(50), CGFloat(120)), (120, 120), (190, 190), (240, 240), (241, 240), (900, 240), (.infinity, 240)] {
            for state in [NotchState.open(nil), .toast] {
                #expect(geometry.shapeSize(for: state, contentHeight: content).height == 32 + expected, "\(content) \(state)")
            }
        }
    }

    // MARK: the panel is larger than the notch

    @Test func aPointInsideTheLargePanelButOutsideASmallerNotchIsOutside() {
        let screen = Self.macBook14
        let geometry = NotchGeometry(screen: screen, config: NotchLayoutConfig(openWidth: 480))
        let panel = geometry.panelFrame(in: screen.frame)
        let centre = screen.frame.midX + geometry.centerOffset
        let top = screen.frame.maxY
        // The narrowest notch with the least content is 480 x 152; its hit area adds 8 pt on each side (40 while dragging).
        let beside = [centre - 440, centre - 300, centre + 300, centre + 440].map { CGPoint(x: $0, y: top - 100) }
        let below = [top - 152 - 60, top - 250, top - 268].map { CGPoint(x: centre, y: $0) }
        let corners = [CGPoint(x: panel.minX + 2, y: panel.minY + 2), CGPoint(x: panel.maxX - 2, y: panel.minY + 2)]
        for state in [NotchState.open(nil), .toast] {
            for point in beside + below + corners {
                #expect(panel.contains(point))
                for dragging in [false, true] {
                    let zone = geometry.pointerZone(at: point, state: state, contentHeight: 120, dragging: dragging, in: screen.frame)
                    #expect(zone == .outside, "\(state) dragging \(dragging) \(point)")
                }
            }
            // The same notch does count points inside it.
            for point in [CGPoint(x: centre, y: top - 100), CGPoint(x: centre + 230, y: top - 100), CGPoint(x: centre, y: top - 145)] {
                #expect(geometry.pointerZone(at: point, state: state, contentHeight: 120, in: screen.frame) == .notch, "\(state) \(point)")
            }
        }
    }

    @Test func theZoneOfAnyStateIsItsShapeAndNotThePanelEverywhereOnThePanel() {
        let screen = Self.macBook14
        for config in [NotchLayoutConfig(), NotchLayoutConfig(openWidth: 480), NotchLayoutConfig(openWidth: 900)] {
            let geometry = NotchGeometry(screen: screen, config: config)
            let panel = geometry.panelFrame(in: screen.frame)
            for (state, height) in [(NotchState.open(nil), CGFloat(120)), (.open(nil), 240), (.toast, 190), (.closed, 190)] {
                let hit = geometry.hitRect(for: state, contentHeight: height, in: screen.frame)
                var wrong = 0
                for x in stride(from: panel.minX + 1, to: panel.maxX, by: 7) {
                    for y in stride(from: panel.minY + 1, to: panel.maxY, by: 7) {
                        let point = CGPoint(x: x, y: y)
                        let inside = geometry.pointerZone(at: point, state: state, contentHeight: height, in: screen.frame) != .outside
                        if inside != hit.contains(point) { wrong += 1 }
                    }
                }
                #expect(wrong == 0, "\(state) \(height) at \(config.openWidth)")
            }
        }
    }

    @Test func theHitAreaOfTheWidestTallestOpenNotchGrowsWithIt() {
        let geometry = NotchGeometry(screen: Self.macBook14, config: NotchLayoutConfig(openWidth: 900))
        let rect = geometry.hitRect(for: .open(nil), contentHeight: 240, in: Self.macBook14.frame)
        #expect(rect == CGRect(x: 754.5 - 450 - 8, y: 982 - (32 + 240) - 8, width: 900 + 16, height: 32 + 240 + 8 + 1))
        let drag = geometry.dragHitRect(for: .open(nil), contentHeight: 240, in: Self.macBook14.frame)
        #expect(drag == CGRect(x: 754.5 - 450 - 40, y: 982 - (32 + 240) - 40, width: 900 + 80, height: 32 + 240 + 40 + 1))
        // The shape never passes the fixed panel's edges.
        #expect(geometry.panelFrame(in: Self.macBook14.frame).contains(CGRect(x: 754.5 - 450, y: 982 - 272, width: 900, height: 272)))
    }

    @Test func panelIsTopCentredAndMaxSized() {
        let geometry = NotchGeometry(screen: Self.external, config: NotchLayoutConfig())
        let frame = geometry.panelFrame(in: Self.external.frame)
        // As wide as the widest open notch and as tall as the notch plus the tallest content a tab gets.
        #expect(frame == CGRect(x: 1512 + 960 - 450, y: 1080 - 265, width: 900, height: 265))
    }

    @Test func thePanelDoesNotChangeWithTheSizeSettings() {
        let small = NotchGeometry(screen: Self.external, config: NotchLayoutConfig(openWidth: 480))
        let large = NotchGeometry(screen: Self.external, config: NotchLayoutConfig(openWidth: 900))
        #expect(small.panelFrame(in: Self.external.frame) == large.panelFrame(in: Self.external.frame))
        #expect(small.panelSize == CGSize(width: 900, height: 25 + 240))
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
        #expect(geometry.panelFrame(in: Self.externalAboveLeft.frame) == CGRect(x: -490, y: 2062 - 265, width: 900, height: 265))
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

    @Test func layoutConfigReadsTheOpenWidthSetting() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        #expect(NotchLayoutConfig(settings: settings).openWidth == 600)
        settings.set(850, for: InterfaceSettings.openWidth)
        #expect(NotchLayoutConfig(settings: settings).openWidth == 850)
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
        for height in stride(from: NotchTab.heightRange.lowerBound, through: NotchGeometry.maxContentHeight + 10, by: 10) {
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
            NotchLayoutConfig(virtualNotchWidth: 120, virtualNotchHeight: 24, openWidth: 480),
            NotchLayoutConfig(virtualNotchWidth: 300, virtualNotchHeight: 40, openWidth: 900),
            // Past the ends of both ranges: held to them.
            NotchLayoutConfig(virtualNotchWidth: 300, virtualNotchHeight: 40, openWidth: 5000),
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
