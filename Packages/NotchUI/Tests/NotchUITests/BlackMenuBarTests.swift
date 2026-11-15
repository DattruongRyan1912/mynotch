import AppKit
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import NotchUI

/// The black menu bar that hides a MacBook's notch: the setting, the band that is laid over the menu bar's own rectangle on each
/// display, and which displays get one. Pure rules over screen facts; nothing here shows a window.
@Suite struct BlackMenuBarTests {
    // MARK: the setting

    @Test func itIsOffUntilTheUserTurnsItOn() {
        #expect(SettingsStore(defaults: makeIsolatedDefaults()).value(InterfaceSettings.blackMenuBar) == .off)
        #expect(InterfaceSettings.blackMenuBar.name == "interface.blackMenuBar")
    }

    @Test func theModesKeepTheirStoredNamesSoAChoiceMadeBeforeStillMeansTheSame() {
        #expect(BlackMenuBar.allCases.map(\.rawValue) == ["off", "notchedScreens", "allScreens"])
        let defaults = makeIsolatedDefaults()
        defaults.set(Data("\"notchedScreens\"".utf8), forKey: InterfaceSettings.blackMenuBar.name)
        #expect(SettingsStore(defaults: defaults).value(InterfaceSettings.blackMenuBar) == .notchedScreens)
    }

    @Test func theModeIsKeptForTheNextLaunch() {
        let defaults = makeIsolatedDefaults()
        for mode in BlackMenuBar.allCases {
            SettingsStore(defaults: defaults).set(mode, for: InterfaceSettings.blackMenuBar)
            #expect(SettingsStore(defaults: defaults).value(InterfaceSettings.blackMenuBar) == mode)
        }
    }

    @Test func anUnknownStoredModeIsOff() {
        let defaults = makeIsolatedDefaults()
        defaults.set(Data("\"everywhere\"".utf8), forKey: InterfaceSettings.blackMenuBar.name)
        #expect(SettingsStore(defaults: defaults).value(InterfaceSettings.blackMenuBar) == .off)
    }

    // MARK: the band's frame

    /// A MacBook 14" in its default mode, an external display on its right, one above-left of the MacBook, and the MacBook in its two
    /// other scaled modes, which report their own points and their own menu bar height.
    static let screens: [(name: String, frame: CGRect, menuBar: CGFloat)] = [
        ("macBook14", NotchGeometryTests.macBook14.frame, NotchGeometryTests.macBook14.menuBarHeight),
        ("external", NotchGeometryTests.external.frame, NotchGeometryTests.external.menuBarHeight),
        ("externalAboveLeft", NotchGeometryTests.externalAboveLeft.frame, NotchGeometryTests.externalAboveLeft.menuBarHeight),
        ("moreSpace", CGRect(x: 0, y: 0, width: 1800, height: 1169), 37),
        ("largerText", CGRect(x: 0, y: 0, width: 1352, height: 878), 32),
        ("externalBelow", CGRect(x: -300, y: -1440, width: 2560, height: 1440), 24),
    ]

    @Test func theBandIsExactlyTheMenuBarsRectangleAtTheTopOfTheScreen() throws {
        for screen in Self.screens {
            let band = try #require(MenuBarBand.frame(screenFrame: screen.frame, menuBarHeight: screen.menuBar), "\(screen.name)")
            #expect(band.minX == screen.frame.minX, "\(screen.name) starts at the screen's left edge")
            #expect(band.width == screen.frame.width, "\(screen.name) is as wide as the screen")
            #expect(band.maxY == screen.frame.maxY, "\(screen.name) reaches the screen's top edge")
            #expect(band.height == screen.menuBar, "\(screen.name) is as tall as the menu bar")
            #expect(screen.frame.contains(band), "\(screen.name) stays on its own screen")
        }
    }

    @Test func theBandOfTheMacBookIsTheMenuBarNotTheNotch() throws {
        // The notch is 32 pt (the safe area) and the menu bar 37: the band is the menu bar's, which is what has to turn black.
        let screen = NotchGeometryTests.macBook14
        #expect(MenuBarBand.frame(screenFrame: screen.frame, menuBarHeight: screen.menuBarHeight) == CGRect(x: 0, y: 945, width: 1512, height: 37))
    }

    @Test func theBandOfADisplayAboveAndLeftOfTheMainOneFollowsItsGlobalPosition() throws {
        let screen = NotchGeometryTests.externalAboveLeft
        #expect(MenuBarBand.frame(screenFrame: screen.frame, menuBarHeight: 25) == CGRect(x: -1000, y: 982 + 1080 - 25, width: 1920, height: 25))
    }

    @Test func aMenuBarThatTakesNoRoomMakesNoBand() {
        #expect(MenuBarBand.frame(screenFrame: NotchGeometryTests.macBook14.frame, menuBarHeight: 0) == nil)
        #expect(MenuBarBand.frame(screenFrame: NotchGeometryTests.macBook14.frame, menuBarHeight: -3) == nil)
    }

    // MARK: which displays get one

    func screen(_ id: CGDirectDisplayID, notch: Bool, menuBar: CGFloat = 37) -> MenuBarBandScreen {
        MenuBarBandScreen(
            id: id, frame: CGRect(x: CGFloat(id) * 2000, y: 0, width: 1512, height: 982), menuBarHeight: menuBar, hasHardwareNotch: notch
        )
    }

    @Test func offMakesNoBandOnAnyDisplay() {
        let plan = MenuBarBand.plan(mode: .off, screens: [screen(1, notch: true), screen(2, notch: false)], fullscreen: [])
        #expect(plan.isEmpty)
    }

    @Test func notchedScreensCoverOnlyTheDisplaysWithAHardwareNotch() {
        let plan = MenuBarBand.plan(
            mode: .notchedScreens, screens: [screen(1, notch: true), screen(2, notch: false), screen(3, notch: true)], fullscreen: []
        )
        #expect(Set(plan.keys) == [1, 3])
    }

    @Test func allScreensCoverEveryDisplay() {
        let plan = MenuBarBand.plan(
            mode: .allScreens, screens: [screen(1, notch: true), screen(2, notch: false), screen(3, notch: true)], fullscreen: []
        )
        #expect(Set(plan.keys) == [1, 2, 3])
    }

    @Test func aBandIsTheFrameOfItsOwnDisplay() {
        let first = screen(1, notch: true, menuBar: 37)
        let second = screen(2, notch: false, menuBar: 24)
        let plan = MenuBarBand.plan(mode: .allScreens, screens: [first, second], fullscreen: [])
        #expect(plan[1] == MenuBarBand.frame(screenFrame: first.frame, menuBarHeight: 37))
        #expect(plan[2] == MenuBarBand.frame(screenFrame: second.frame, menuBarHeight: 24))
    }

    @Test func aFullscreenDisplayHasNoBandWhateverTheMode() {
        let screens = [screen(1, notch: true), screen(2, notch: false)]
        for mode in [BlackMenuBar.notchedScreens, .allScreens] {
            let plan = MenuBarBand.plan(mode: mode, screens: screens, fullscreen: [1])
            #expect(plan[1] == nil, "\(mode): the menu bar is hidden there, and the band would cover the app")
        }
        #expect(MenuBarBand.plan(mode: .allScreens, screens: screens, fullscreen: [1])[2] != nil, "the other display keeps its own")
    }

    @Test func aMenuBarThatIsAutoHiddenHasNoBandBecauseTheAppsWindowsReachTheTop() {
        // The screen reports no room taken at the top then; a band would be drawn over the top of every app window.
        let hidden = screen(1, notch: true, menuBar: 0)
        for mode in [BlackMenuBar.notchedScreens, .allScreens] {
            #expect(MenuBarBand.plan(mode: mode, screens: [hidden], fullscreen: []).isEmpty, "\(mode)")
        }
    }

    @Test func theFullTableOfModeNotchMenuBarAndFullscreen() {
        for mode in BlackMenuBar.allCases {
            for notch in [true, false] {
                for menuBar in [CGFloat(0), 24] {
                    for fullscreen in [true, false] {
                        let plan = MenuBarBand.plan(
                            mode: mode, screens: [screen(7, notch: notch, menuBar: menuBar)], fullscreen: fullscreen ? [7] : []
                        )
                        let expected = switch mode {
                        case .off: false
                        case .notchedScreens: notch && menuBar > 0 && !fullscreen
                        case .allScreens: menuBar > 0 && !fullscreen
                        }
                        #expect(!plan.isEmpty == expected, "\(mode) notch=\(notch) menuBar=\(menuBar) fullscreen=\(fullscreen)")
                    }
                }
            }
        }
    }

    // MARK: reading a real screen

    @Test func aRealScreenIsReadAsItsFrameItsMenuBarAndWhetherItHasANotch() {
        for real in NSScreen.screens {
            guard let read = MenuBarBandScreen(real) else { continue }
            #expect(read.frame == real.frame)
            #expect(read.menuBarHeight == real.frame.maxY - real.visibleFrame.maxY, "the raw height, 0 while the menu bar is auto-hidden")
            #expect(read.hasHardwareNotch == (NotchGeometry(screen: ScreenDescriptor(real), config: NotchLayoutConfig()).kind == .hardware))
        }
    }
}
