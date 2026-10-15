import AppKit
import MyNotchCore
import MyNotchTestSupport
import Observation
import SwiftUI
import Testing
@testable import NotchUI

/// Which look the notch has (classic black or Liquid Glass), what it is drawn on in each state, and how the choice meets the
/// older "Kính mờ" setting of the open notch.
@Suite struct NotchLookTests {
    nonisolated final class Changed: @unchecked Sendable {
        nonisolated(unsafe) var value = false
    }

    let defaults = makeIsolatedDefaults()

    var settings: SettingsStore { SettingsStore(defaults: defaults) }

    func theme(_ settings: SettingsStore) -> NotchTheme {
        NotchTheme(settings: settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter())
    }

    // MARK: the setting

    @Test func theNotchIsClassicAndUntintedUntilTheUserChoosesOtherwise() {
        #expect(settings.value(InterfaceSettings.look) == .classic)
        #expect(!settings.value(InterfaceSettings.glassTint))
    }

    @Test func theLooksKeepTheirStoredNames() {
        #expect(NotchLook.allCases.map(\.rawValue) == ["classic", "liquidGlass"])
        defaults.set(Data("\"liquidGlass\"".utf8), forKey: InterfaceSettings.look.name)
        #expect(settings.value(InterfaceSettings.look) == .liquidGlass)
        #expect(InterfaceSettings.look.name == "interface.look")
        #expect(InterfaceSettings.glassTint.name == "interface.glassTint")
    }

    @Test func theChoiceAndTheTintAreKeptForTheNextLaunch() {
        for look in NotchLook.allCases {
            settings.set(look, for: InterfaceSettings.look)
            #expect(settings.value(InterfaceSettings.look) == look)
        }
        settings.set(true, for: InterfaceSettings.glassTint)
        #expect(settings.value(InterfaceSettings.glassTint))
    }

    @Test func anUnknownOrMistypedStoredLookIsClassic() {
        defaults.set(Data("\"holographic\"".utf8), forKey: InterfaceSettings.look.name)
        #expect(settings.value(InterfaceSettings.look) == .classic)
        defaults.set(Data("7".utf8), forKey: InterfaceSettings.look.name)
        #expect(settings.value(InterfaceSettings.look) == .classic)
    }

    // MARK: the older glass setting

    @Test func aStoreFromBeforeTheLookExistedKeepsItsLookAndItsBlur() {
        // What an earlier build wrote: the blur on, no look at all.
        settings.set(true, for: InterfaceSettings.glass)
        let theme = theme(settings)
        #expect(theme.look == .classic)
        #expect(theme.surface(for: .open(nil)) == .material)
        #expect(theme.surface(for: .compact) == .solid)
    }

    @Test func choosingLiquidGlassLeavesTheBlurSettingAloneAndGoingBackBringsItBack() {
        let settings = settings
        settings.set(true, for: InterfaceSettings.glass)
        let theme = theme(settings)
        settings.set(.liquidGlass, for: InterfaceSettings.look)
        #expect(settings.value(InterfaceSettings.glass), "the user's blur choice is not overwritten")
        #expect(theme.surface(for: .open(nil)) == .liquidGlass(tinted: false))
        settings.set(.classic, for: InterfaceSettings.look)
        #expect(theme.surface(for: .open(nil)) == .material)
    }

    @Test func liquidGlassSupersedesTheBlurWhicheverWayItIsSet() {
        for blur in [false, true] {
            for state in [NotchState.closed, .compact, .open(nil), .toast] {
                #expect(
                    NotchSurface.resolve(look: .liquidGlass, classicGlass: blur, tinted: false, state: state) == .liquidGlass(tinted: false),
                    "blur \(blur) \(state)"
                )
            }
        }
    }

    // MARK: what each look is drawn on

    @Test func classicIsBlackInEveryStateAndTheBlurOnlyChangesTheExpandedOnes() {
        for state in [NotchState.closed, .compact, .open(nil), .open("a"), .toast] {
            #expect(NotchSurface.resolve(look: .classic, classicGlass: false, tinted: false, state: state) == .solid, "\(state)")
        }
        for state in [NotchState.closed, .compact] {
            #expect(NotchSurface.resolve(look: .classic, classicGlass: true, tinted: false, state: state) == .solid, "\(state)")
        }
        for state in [NotchState.open(nil), .open("a"), .toast] {
            #expect(NotchSurface.resolve(look: .classic, classicGlass: true, tinted: false, state: state) == .material, "\(state)")
        }
    }

    @Test func liquidGlassIsGlassInEveryStateIncludingTheCollapsedNotch() {
        for state in [NotchState.closed, .compact, .open(nil), .open("a"), .toast] {
            let surface = NotchSurface.resolve(look: .liquidGlass, classicGlass: false, tinted: false, state: state)
            #expect(surface == .liquidGlass(tinted: false), "\(state)")
            #expect(surface.isLiquidGlass)
        }
    }

    @Test func theTintOnlyTouchesLiquidGlass() {
        for state in [NotchState.closed, .compact, .open(nil), .toast] {
            #expect(NotchSurface.resolve(look: .liquidGlass, classicGlass: false, tinted: true, state: state) == .liquidGlass(tinted: true))
            #expect(
                NotchSurface.resolve(look: .classic, classicGlass: false, tinted: true, state: state)
                    == NotchSurface.resolve(look: .classic, classicGlass: false, tinted: false, state: state)
            )
        }
    }

    @Test func onlyLiquidGlassIsLiquidGlass() {
        #expect(!NotchSurface.solid.isLiquidGlass)
        #expect(!NotchSurface.material.isLiquidGlass)
        #expect(NotchSurface.liquidGlass(tinted: true).isLiquidGlass)
    }

    // MARK: the theme follows the settings

    @Test func theThemeReadsTheLookAndTheTintLive() {
        let settings = settings
        let theme = theme(settings)
        #expect(theme.surface(for: .compact) == .solid)
        let changed = Changed()
        withObservationTracking { _ = theme.surface(for: .compact) } onChange: { changed.value = true }
        settings.set(.liquidGlass, for: InterfaceSettings.look)
        #expect(changed.value)
        #expect(theme.surface(for: .compact) == .liquidGlass(tinted: false))

        let tintChanged = Changed()
        withObservationTracking { _ = theme.surface(for: .compact) } onChange: { tintChanged.value = true }
        settings.set(true, for: InterfaceSettings.glassTint)
        #expect(tintChanged.value)
        #expect(theme.surface(for: .compact) == .liquidGlass(tinted: true))
    }

    @Test func aFloatingWindowGetsGlassOrBlackAndNeverTheOpenNotchsBlur() {
        let settings = settings
        settings.set(true, for: InterfaceSettings.glass)
        let theme = theme(settings)
        #expect(theme.floatingSurface == .solid)
        settings.set(.liquidGlass, for: InterfaceSettings.look)
        settings.set(true, for: InterfaceSettings.glassTint)
        #expect(theme.floatingSurface == .liquidGlass(tinted: true))
    }

    @Test func theInterfaceTellsAWindowOutsideTheNotchWhichSurfaceToDrawOn() {
        let settings = settings
        let theme = theme(settings)
        let interface = NotchInterface()
        #expect(interface.surface == .solid, "before a theme is followed")
        interface.follow(settings, theme: theme)
        #expect(interface.surface == .solid)
        let changed = Changed()
        withObservationTracking { _ = interface.surface } onChange: { changed.value = true }
        settings.set(.liquidGlass, for: InterfaceSettings.look)
        #expect(changed.value)
        #expect(interface.surface == .liquidGlass(tinted: false))
    }
}
