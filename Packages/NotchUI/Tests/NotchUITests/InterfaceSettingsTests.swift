import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import NotchUI

/// The interface settings that decide which display shows a notch and how big the open notch is: their defaults, the
/// range each is held to, what is stored, and that a change reaches the code that redraws the notches.
@Suite struct InterfaceSettingsTests {
    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    // MARK: defaults

    @Test func theDefaultsAreWhatTheNotchHasAlwaysDone() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        #expect(settings.value(InterfaceSettings.displayMode) == .all)
        #expect(settings.value(InterfaceSettings.openWidth) == 600)
        #expect(settings.value(InterfaceSettings.virtualNotchWidth) == 185)
        #expect(settings.value(InterfaceSettings.virtualNotchMatchesMenuBar))
    }

    // MARK: display mode

    @Test func theDisplayModesKeepTheirStoredNamesSoAChoiceMadeBeforeStillMeansTheSame() {
        #expect(DisplayMode.allCases.map(\.rawValue) == ["all", "main", "cursor"])
        let defaults = makeIsolatedDefaults()
        defaults.set(Data("\"cursor\"".utf8), forKey: InterfaceSettings.displayMode.name)
        #expect(SettingsStore(defaults: defaults).value(InterfaceSettings.displayMode) == .cursor)
    }

    @Test func theDisplayModeIsKeptForTheNextLaunch() {
        let defaults = makeIsolatedDefaults()
        for mode in DisplayMode.allCases {
            SettingsStore(defaults: defaults).set(mode, for: InterfaceSettings.displayMode)
            #expect(SettingsStore(defaults: defaults).value(InterfaceSettings.displayMode) == mode)
        }
    }

    @Test func anUnknownStoredModeIsTheDefault() {
        let defaults = makeIsolatedDefaults()
        defaults.set(Data("\"everywhere\"".utf8), forKey: InterfaceSettings.displayMode.name)
        #expect(SettingsStore(defaults: defaults).value(InterfaceSettings.displayMode) == .all)
    }

    // MARK: size

    @Test func theOpenWidthIsHeldTo480Through900() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        for (set, read) in [(CGFloat(480), CGFloat(480)), (900, 900), (700, 700), (100, 480), (479, 480), (901, 900), (5000, 900)] {
            settings.set(Double(set), for: InterfaceSettings.openWidth)
            #expect(settings.value(InterfaceSettings.openWidth) == Double(read), "\(set)")
        }
    }

    @Test func aWidthStoredOutsideTheRangeIsReadWithinIt() {
        let defaults = makeIsolatedDefaults()
        defaults.set(Data("1200".utf8), forKey: InterfaceSettings.openWidth.name)
        #expect(SettingsStore(defaults: defaults).value(InterfaceSettings.openWidth) == 900)
    }

    @Test func theWidthIsHeldToTheLimitsTheGeometryAndThePageUse() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        let widths = NotchGeometry.openWidthLimits
        settings.set(Double(widths.lowerBound) - 1, for: InterfaceSettings.openWidth)
        #expect(settings.value(InterfaceSettings.openWidth) == Double(widths.lowerBound))
        settings.set(Double(widths.upperBound) + 1, for: InterfaceSettings.openWidth)
        #expect(settings.value(InterfaceSettings.openWidth) == Double(widths.upperBound))
    }

    @Test func theWidthIsKeptForTheNextLaunchAndResetGoesBackToTheDefault() {
        let defaults = makeIsolatedDefaults()
        SettingsStore(defaults: defaults).set(840, for: InterfaceSettings.openWidth)
        let second = SettingsStore(defaults: defaults)
        #expect(second.value(InterfaceSettings.openWidth) == 840)
        second.reset(InterfaceSettings.openWidth)
        #expect(second.value(InterfaceSettings.openWidth) == 600)
    }

    @Test func aMaxHeightStoredByAnEarlierVersionIsIgnored() {
        // The height of the open notch is no setting any more; what an earlier build stored is left where it is and unread.
        let defaults = makeIsolatedDefaults()
        defaults.set(Data("250".utf8), forKey: "interface.maxOpenHeight")
        let settings = SettingsStore(defaults: defaults)
        let config = NotchLayoutConfig(settings: settings)
        #expect(config == NotchLayoutConfig(settings: SettingsStore(defaults: makeIsolatedDefaults())))
        let geometry = NotchGeometry(screen: NotchGeometryTests.macBook14, config: config)
        let expected: CGFloat = 32 + 240
        #expect(geometry.shapeSize(for: .open(nil), contentHeight: 240).height == expected)
    }

    @Test func theSettingsKeysAreTheOnesTheAppStoresThemUnder() {
        #expect(InterfaceSettings.openWidth.name == "interface.openWidth")
        #expect(InterfaceSettings.displayMode.name == "interface.displayMode")
        #expect(InterfaceSettings.accent.name == "interface.accent")
        #expect(InterfaceSettings.glass.name == "interface.glass")
        #expect(InterfaceSettings.swipeToOpen.name == "interface.swipeToOpen")
        #expect(InterfaceSettings.swipeSensitivity.name == "interface.swipeSensitivity")
        #expect(InterfaceSettings.haptics.name == "interface.haptics")
    }

    // MARK: look and gestures

    @Test func theLookAndGesturesStartTheWayTheBriefAsks() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        #expect(settings.value(InterfaceSettings.accent) == .system)
        #expect(settings.value(InterfaceSettings.glass) == false)
        #expect(settings.value(InterfaceSettings.swipeToOpen))
        #expect(settings.value(InterfaceSettings.swipeSensitivity) == .medium)
        #expect(settings.value(InterfaceSettings.haptics))
    }

    @Test func theLookAndGestureChoicesAreKeptForTheNextLaunch() {
        let defaults = makeIsolatedDefaults()
        let first = SettingsStore(defaults: defaults)
        first.set(true, for: InterfaceSettings.glass)
        first.set(false, for: InterfaceSettings.swipeToOpen)
        first.set(.high, for: InterfaceSettings.swipeSensitivity)
        let second = SettingsStore(defaults: defaults)
        #expect(second.value(InterfaceSettings.glass))
        #expect(second.value(InterfaceSettings.swipeToOpen) == false)
        #expect(second.value(InterfaceSettings.swipeSensitivity) == .high)
    }

    @Test func anUnknownSensitivityIsTheDefault() {
        let defaults = makeIsolatedDefaults()
        defaults.set(Data("\"extreme\"".utf8), forKey: InterfaceSettings.swipeSensitivity.name)
        #expect(SettingsStore(defaults: defaults).value(InterfaceSettings.swipeSensitivity) == .medium)
    }

    // MARK: live

    final class Seen {
        var configs: [NotchLayoutConfig] = []
    }

    @Test func aChangeOfAnySizeReachesTheLoopThatRedrawsTheNotches() async {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        let seen = Seen()
        let loop = Task {
            for await config in Observations({ NotchLayoutConfig(settings: settings) }) { seen.configs.append(config) }
        }
        defer { loop.cancel() }
        #expect(await eventually { seen.configs.last?.openWidth == 600 })
        settings.set(800, for: InterfaceSettings.openWidth)
        #expect(await eventually { seen.configs.last?.openWidth == 800 })
        settings.set(false, for: InterfaceSettings.virtualNotchMatchesMenuBar)
        settings.set(36, for: InterfaceSettings.virtualNotchHeight)
        #expect(await eventually { seen.configs.last?.virtualNotchHeight == 36 })
        settings.set(210, for: InterfaceSettings.virtualNotchWidth)
        #expect(await eventually { seen.configs.last?.virtualNotchWidth == 210 })
        #expect(seen.configs.last?.openWidth == 800)
    }

    @Test func theGeometryOfADisplayFollowsTheSettingsAtOnce() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        let screen = NotchGeometryTests.macBook14
        settings.set(880, for: InterfaceSettings.openWidth)
        let geometry = NotchGeometry(screen: screen, config: NotchLayoutConfig(settings: settings))
        #expect(geometry.shapeSize(for: .open(nil), contentHeight: 190) == CGSize(width: 880, height: 32 + 190))
        settings.set(520, for: InterfaceSettings.openWidth)
        let narrower = NotchGeometry(screen: screen, config: NotchLayoutConfig(settings: settings))
        #expect(narrower.shapeSize(for: .open(nil), contentHeight: 190) == CGSize(width: 520, height: 32 + 190))
        #expect(narrower != geometry)
    }
}
