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
        #expect(settings.value(InterfaceSettings.maxOpenHeight) == 300)
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

    @Test func theMaxHeightIsHeldTo200Through400() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        for (set, read) in [(CGFloat(200), CGFloat(200)), (400, 400), (300, 300), (50, 200), (199, 200), (401, 400), (9000, 400)] {
            settings.set(Double(set), for: InterfaceSettings.maxOpenHeight)
            #expect(settings.value(InterfaceSettings.maxOpenHeight) == Double(read), "\(set)")
        }
    }

    @Test func aSizeStoredOutsideTheRangeIsReadWithinIt() {
        let defaults = makeIsolatedDefaults()
        defaults.set(Data("1200".utf8), forKey: InterfaceSettings.openWidth.name)
        defaults.set(Data("12".utf8), forKey: InterfaceSettings.maxOpenHeight.name)
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.value(InterfaceSettings.openWidth) == 900)
        #expect(settings.value(InterfaceSettings.maxOpenHeight) == 200)
    }

    @Test func theSizesAreKeptForTheNextLaunchAndResetGoesBackToTheDefaults() {
        let defaults = makeIsolatedDefaults()
        let first = SettingsStore(defaults: defaults)
        first.set(840, for: InterfaceSettings.openWidth)
        first.set(360, for: InterfaceSettings.maxOpenHeight)
        let second = SettingsStore(defaults: defaults)
        #expect(second.value(InterfaceSettings.openWidth) == 840)
        #expect(second.value(InterfaceSettings.maxOpenHeight) == 360)
        second.reset(InterfaceSettings.openWidth)
        second.reset(InterfaceSettings.maxOpenHeight)
        #expect(second.value(InterfaceSettings.openWidth) == 600)
        #expect(second.value(InterfaceSettings.maxOpenHeight) == 300)
    }

    @Test func theSettingsKeysAreTheOnesTheAppStoresThemUnder() {
        #expect(InterfaceSettings.openWidth.name == "interface.openWidth")
        #expect(InterfaceSettings.maxOpenHeight.name == "interface.maxOpenHeight")
        #expect(InterfaceSettings.displayMode.name == "interface.displayMode")
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
        settings.set(250, for: InterfaceSettings.maxOpenHeight)
        #expect(await eventually { seen.configs.last?.maxContentHeight == 250 })
        settings.set(false, for: InterfaceSettings.virtualNotchMatchesMenuBar)
        settings.set(36, for: InterfaceSettings.virtualNotchHeight)
        #expect(await eventually { seen.configs.last?.virtualNotchHeight == 36 })
        settings.set(210, for: InterfaceSettings.virtualNotchWidth)
        #expect(await eventually { seen.configs.last?.virtualNotchWidth == 210 })
        #expect(seen.configs.last?.openWidth == 800)
        #expect(seen.configs.last?.maxContentHeight == 250)
    }

    @Test func theGeometryOfADisplayFollowsTheSettingsAtOnce() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        let screen = NotchGeometryTests.macBook14
        settings.set(880, for: InterfaceSettings.openWidth)
        settings.set(400, for: InterfaceSettings.maxOpenHeight)
        let geometry = NotchGeometry(screen: screen, config: NotchLayoutConfig(settings: settings))
        #expect(geometry.shapeSize(for: .open(nil), contentHeight: 380) == CGSize(width: 880, height: 32 + 380))
        settings.set(200, for: InterfaceSettings.maxOpenHeight)
        let shorter = NotchGeometry(screen: screen, config: NotchLayoutConfig(settings: settings))
        #expect(shorter.shapeSize(for: .open(nil), contentHeight: 380) == CGSize(width: 880, height: 32 + 200))
        #expect(shorter != geometry)
    }
}
