import AppKit
import MyNotchCore
import Testing
@testable import NotchUI

/// The window that is the black menu bar, and the controller that keeps one on each display that is to have it. Every band that is
/// shown here is far off every screen (the place `ActiveGlassTests` uses), so none of them is ever drawn on the user's menu bar.
@Suite struct MenuBarBandWindowTests {
    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// A display of 1512 x 982 whose top-left corner is `x` points right of -30000, -30000: nowhere.
    func display(_ id: CGDirectDisplayID, x: CGFloat = 0, notch: Bool = true, menuBar: CGFloat = 37) -> MenuBarBandScreen {
        MenuBarBandScreen(
            id: id, frame: CGRect(x: -30000 + x, y: -30000, width: 1512, height: 982), menuBarHeight: menuBar, hasHardwareNotch: notch
        )
    }

    func makeBands(_ hiding: CaptureHiding = .never) -> (bands: MenuBarBands, interface: NotchInterface) {
        let interface = NotchInterface(captureHiding: hiding)
        return (MenuBarBands(interface: interface), interface)
    }

    // MARK: the window

    @Test func theWindowIsABorderlessBlackRectangleThatNeverTakesTheMouseOrTheKeyboard() {
        let window = MenuBarBandWindow(frame: CGRect(x: -30000, y: -30000, width: 1512, height: 37), interface: NotchInterface())
        defer { window.close() }
        #expect(window.styleMask.contains(.borderless))
        #expect(window.styleMask.contains(.nonactivatingPanel))
        #expect(window.ignoresMouseEvents, "a click goes through to the menu bar")
        #expect(!window.canBecomeKey)
        #expect(!window.canBecomeMain)
        #expect(!window.isKeyWindow)
        #expect(window.isOpaque)
        let black = window.backgroundColor.usingColorSpace(.sRGB)
        #expect(black?.redComponent == 0 && black?.greenComponent == 0 && black?.blueComponent == 0 && black?.alphaComponent == 1)
        #expect(!window.hasShadow)
        #expect(window.contentView.map { $0.subviews.isEmpty } ?? true, "it is only a colour: nothing to draw, lay out or keep in memory")
    }

    @Test func theWindowIsOnEverySpaceAndStaysWhereItIsButNeverOverAFullscreenApp() {
        let window = MenuBarBandWindow(frame: .zero, interface: NotchInterface())
        defer { window.close() }
        #expect(window.collectionBehavior == [.canJoinAllSpaces, .stationary, .ignoresCycle])
        #expect(!window.collectionBehavior.contains(.fullScreenAuxiliary), "a fullscreen app's Space does not get it")
    }

    @Test func theWindowSurvivesWhatWouldHideAnOrdinaryPanel() {
        let window = MenuBarBandWindow(frame: .zero, interface: NotchInterface())
        defer { window.close() }
        #expect(!window.hidesOnDeactivate, "Settings activating and closing must not take the band away")
        #expect(!window.canHide, "nor hiding MyNotch with ⌘H")
        #expect(!window.isReleasedWhenClosed)
        #expect(window.animationBehavior == .none)
        #expect(window.isExcludedFromWindowsMenu)
    }

    @Test func theWindowSitsJustBelowTheMenuBarSoItsItemsAreDrawnOverTheBlack() {
        #expect(MenuBarBandWindow.level == .mainMenu - 1)
        #expect(MenuBarBandWindow.level.rawValue == Int(CGWindowLevelForKey(.mainMenuWindow)) - 1, "the level the window server gives the menu bar, less one")
        #expect(MenuBarBandWindow.level < .mainMenu, "the menu bar is above it")
        #expect(MenuBarBandWindow.level < .statusBar, "and so are the status items")
        #expect(MenuBarBandWindow.level > .modalPanel, "above every window an app normally has, so none is over the band")
        #expect(MenuBarBandWindow.level > .floating)
        let window = MenuBarBandWindow(frame: .zero, interface: NotchInterface())
        defer { window.close() }
        #expect(window.level == MenuBarBandWindow.level)
    }

    @Test func theNotchIsDrawnOverTheBand() {
        let notch = NotchPanel(frame: .zero)
        defer { notch.close() }
        #expect(MenuBarBandWindow.level < notch.level, "the Liquid Glass or black notch sits over the black, never under it")
    }

    // MARK: one per display

    @Test func aBandIsShownAtTheMenuBarOfEachDisplayThatHasOne() {
        let (bands, _) = makeBands()
        defer { bands.close() }
        let left = display(1), right = display(2, x: 2000, notch: false, menuBar: 24)
        bands.update(mode: .allScreens, screens: [left, right], fullscreen: [])
        #expect(Set(bands.windows.keys) == [1, 2])
        #expect(bands.windows[1]?.frame == CGRect(x: -30000, y: -30000 + 982 - 37, width: 1512, height: 37))
        #expect(bands.windows[2]?.frame == CGRect(x: -28000, y: -30000 + 982 - 24, width: 1512, height: 24))
        #expect(bands.windows.values.allSatisfy { $0.isVisible })
        #expect(bands.windows.values.allSatisfy { !$0.isKeyWindow })
    }

    @Test func theModesChooseTheDisplaysAndOffTakesEveryBandAway() {
        let (bands, _) = makeBands()
        defer { bands.close() }
        let screens = [display(1), display(2, x: 2000, notch: false)]
        bands.update(mode: .notchedScreens, screens: screens, fullscreen: [])
        #expect(Set(bands.windows.keys) == [1])
        let first = bands.windows[1]
        bands.update(mode: .allScreens, screens: screens, fullscreen: [])
        #expect(Set(bands.windows.keys) == [1, 2])
        #expect(bands.windows[1] === first, "the band that stays is not made again")
        bands.update(mode: .off, screens: screens, fullscreen: [])
        #expect(bands.windows.isEmpty)
        #expect(first?.isVisible == false, "taken away, not left behind")
    }

    @Test func aFullscreenDisplayLosesItsBandAndGetsItBackWhenItIsNoLongerFullscreen() {
        let (bands, _) = makeBands()
        defer { bands.close() }
        let screens = [display(1), display(2, x: 2000)]
        bands.update(mode: .allScreens, screens: screens, fullscreen: [])
        let covered = bands.windows[1]
        bands.update(mode: .allScreens, screens: screens, fullscreen: [1])
        #expect(Set(bands.windows.keys) == [2])
        #expect(covered?.isVisible == false)
        bands.update(mode: .allScreens, screens: screens, fullscreen: [])
        #expect(Set(bands.windows.keys) == [1, 2])
        #expect(bands.windows[1]?.isVisible == true)
    }

    @Test func aMenuBarThatIsAutoHiddenTakesTheBandAwayAndShowingItBringsItBack() {
        let (bands, _) = makeBands()
        defer { bands.close() }
        bands.update(mode: .allScreens, screens: [display(1)], fullscreen: [])
        #expect(bands.windows[1]?.isVisible == true)
        bands.update(mode: .allScreens, screens: [display(1, menuBar: 0)], fullscreen: [])
        #expect(bands.windows.isEmpty)
        bands.update(mode: .allScreens, screens: [display(1)], fullscreen: [])
        #expect(bands.windows[1]?.isVisible == true)
    }

    @Test func aDisplayThatChangesItsModeOrItsMenuBarMovesAndResizesTheSameBand() {
        let (bands, _) = makeBands()
        defer { bands.close() }
        bands.update(mode: .allScreens, screens: [display(1)], fullscreen: [])
        let band = bands.windows[1]
        // Scaled to another resolution, and moved: a new frame and a new menu bar height.
        let scaled = MenuBarBandScreen(
            id: 1, frame: CGRect(x: -30000, y: -29000, width: 1800, height: 1169), menuBarHeight: 32, hasHardwareNotch: true
        )
        bands.update(mode: .allScreens, screens: [scaled], fullscreen: [])
        #expect(bands.windows[1] === band)
        #expect(band?.frame == CGRect(x: -30000, y: -29000 + 1169 - 32, width: 1800, height: 32))
        #expect(band?.isVisible == true)
    }

    @Test func aDisplayThatIsUnpluggedTakesItsBandWithIt() {
        let (bands, _) = makeBands()
        defer { bands.close() }
        bands.update(mode: .allScreens, screens: [display(1), display(2, x: 2000)], fullscreen: [])
        let gone = bands.windows[2]
        bands.update(mode: .allScreens, screens: [display(1)], fullscreen: [])
        #expect(Set(bands.windows.keys) == [1])
        #expect(gone?.isVisible == false)
    }

    @Test func updatingAgainWithTheSameThingsChangesNothing() {
        let (bands, _) = makeBands()
        defer { bands.close() }
        bands.update(mode: .allScreens, screens: [display(1)], fullscreen: [])
        let band = bands.windows[1]
        let number = band?.windowNumber
        for _ in 0..<3 { bands.update(mode: .allScreens, screens: [display(1)], fullscreen: []) }
        #expect(bands.windows[1] === band)
        #expect(band?.windowNumber == number)
        #expect(band?.isVisible == true)
    }

    @Test func closingTakesEveryBandAway() {
        let (bands, _) = makeBands()
        bands.update(mode: .allScreens, screens: [display(1), display(2, x: 2000)], fullscreen: [])
        let all = Array(bands.windows.values)
        bands.close()
        #expect(bands.windows.isEmpty)
        #expect(all.allSatisfy { !$0.isVisible })
    }

    // MARK: recordings

    @Test func theBandIsKeptOutOfRecordingsTheWayTheUserAskedAndIsNeverShownBeforeThat() {
        for (hiding, sharing) in [(CaptureHiding.never, NSWindow.SharingType.readOnly), (.whenCollapsed, .none), (.always, .none)] {
            let (bands, _) = makeBands(hiding)
            defer { bands.close() }
            bands.update(mode: .allScreens, screens: [display(1)], fullscreen: [])
            #expect(bands.windows[1]?.sharingType == sharing, "\(hiding)")
        }
    }

    @Test func theBandFollowsAChangeOfTheCaptureSettingWhileItIsShown() async {
        let (bands, interface) = makeBands(.never)
        defer { bands.close() }
        bands.update(mode: .allScreens, screens: [display(1)], fullscreen: [])
        #expect(bands.windows[1]?.sharingType == .readOnly)
        interface.captureHiding = .always
        #expect(await eventually { bands.windows[1]?.sharingType == NSWindow.SharingType.none })
        interface.captureHiding = .never
        #expect(await eventually { bands.windows[1]?.sharingType == .readOnly })
    }
}
