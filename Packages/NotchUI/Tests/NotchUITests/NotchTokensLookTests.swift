import AppKit
import MyNotchCore
import MyNotchTestSupport
import Observation
import SwiftUI
import Testing
@testable import NotchUI

/// The text tokens that every module draws with. On the classic notch they are the white they have always been. On Liquid
/// Glass they are the system's own primary and secondary colours, which follow the appearance, so module text adapts to glass
/// that is light or dark. Each test runs against a look state of its own (`NotchLookState.current` is a task-local), so none of
/// them can turn the app's real one over for the tests that run beside them.
@Suite struct NotchTokensLookTests {
    nonisolated final class Changed: @unchecked Sendable {
        nonisolated(unsafe) var value = false
    }

    func state(glass: Bool) -> NotchLookState {
        let state = NotchLookState()
        state.isGlass = glass
        return state
    }

    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<400 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test func onTheClassicNotchTheTokensAreExactlyTheWhitesTheyAlwaysWere() {
        NotchLookState.$current.withValue(state(glass: false)) {
            #expect(NotchTokens.primaryText == Color.white)
            #expect(NotchTokens.secondaryText == Color.white.opacity(0.6))
        }
    }

    @Test func onGlassTheyAreTheSystemsPrimaryAndSecondaryColours() {
        NotchLookState.$current.withValue(state(glass: true)) {
            #expect(NotchTokens.primaryText == Color.primary)
            #expect(NotchTokens.secondaryText == Color.secondary)
        }
    }

    @Test func theAppsOwnStateStartsClassicAndIsWhatTheTokensReadUnlessATestSaysOtherwise() {
        #expect(NotchLookState.current === NotchLookState.shared)
        #expect(!NotchLookState.shared.isGlass)
    }

    @Test func aViewThatReadATokenIsToldWhenTheLookChanges() {
        let state = state(glass: false)
        let changed = Changed()
        NotchLookState.$current.withValue(state) {
            withObservationTracking { _ = NotchTokens.primaryText } onChange: { changed.value = true }
        }
        #expect(!changed.value)
        state.isGlass = true
        #expect(changed.value)
    }

    /// A square filled with the token over mid grey in `scheme`, read back as its brightness.
    func brightness(of token: () -> Color, glass: Bool, scheme: ColorScheme) throws -> Double {
        try NotchLookState.$current.withValue(state(glass: glass)) {
            let view = ZStack { Color(.sRGB, white: 0.5); Rectangle().fill(token()).frame(width: 8, height: 8) }
                .environment(\.colorScheme, scheme).frame(width: 12, height: 12)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            return Double(try #require(bitmap.colorAt(x: 6, y: 6)?.usingColorSpace(.sRGB)).redComponent)
        }
    }

    @Test func moduleTextAdaptsToTheSchemeOnGlassAndStaysWhiteOnTheClassicNotch() throws {
        for token in [{ NotchTokens.primaryText }, { NotchTokens.secondaryText }] {
            #expect(try brightness(of: token, glass: true, scheme: .dark) > 0.7, "light on dark glass")
            #expect(try brightness(of: token, glass: true, scheme: .light) < 0.35, "dark on light glass")
            #expect(try brightness(of: token, glass: false, scheme: .dark) > 0.7)
            #expect(try brightness(of: token, glass: false, scheme: .light) > 0.7, "classic is white whatever the scheme is")
        }
    }

    /// A square filled with the primary token, inside `.notchOnDarkBackground()` when `onDark`, over mid grey in `scheme`.
    func tokenBrightness(glass: Bool, scheme: ColorScheme, onDark: Bool) throws -> Double {
        try NotchLookState.$current.withValue(state(glass: glass)) {
            let square = Rectangle().fill(NotchTokens.primaryText).frame(width: 8, height: 8)
            let view = ZStack { Color(.sRGB, white: 0.5); if onDark { square.notchOnDarkBackground() } else { square } }
                .environment(\.colorScheme, scheme).frame(width: 12, height: 12)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            return Double(try #require(bitmap.colorAt(x: 6, y: 6)?.usingColorSpace(.sRGB)).redComponent)
        }
    }

    @Test func aViewOnAFixedDarkBackgroundKeepsLightTextOnGlassInALightAppearance() throws {
        // A floating chip or panel that draws its own black background cannot take the tokens' glass colours in a light appearance:
        // black text on black. The modifier gives it the dark scheme, where they are light.
        #expect(try tokenBrightness(glass: true, scheme: .light, onDark: false) < 0.35, "the tokens follow the light appearance")
        #expect(try tokenBrightness(glass: true, scheme: .light, onDark: true) > 0.7)
        #expect(try tokenBrightness(glass: true, scheme: .dark, onDark: true) > 0.7)
        #expect(try tokenBrightness(glass: false, scheme: .light, onDark: true) > 0.7, "and the classic tokens are white anyway")
    }

    /// What an AppKit drawing gets when a module turns a token into an `NSColor`, in each appearance.
    func appKitBrightness(glass: Bool, appearance: NSAppearance.Name) -> Double {
        NotchLookState.$current.withValue(state(glass: glass)) {
            let color = NSColor(NotchTokens.primaryText)
            var red = 0.0
            NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
                red = Double(color.usingColorSpace(.sRGB)?.redComponent ?? -1)
            }
            return red
        }
    }

    @Test func anNSColorMadeFromATokenOnGlassStillFollowsTheAppearanceItIsDrawnIn() {
        #expect(appKitBrightness(glass: true, appearance: .darkAqua) == 1)
        #expect(appKitBrightness(glass: true, appearance: .aqua) == 0)
        #expect(appKitBrightness(glass: false, appearance: .aqua) == 1)
        #expect(appKitBrightness(glass: false, appearance: .darkAqua) == 1)
    }

    // MARK: the theme keeps the state in step with the setting

    @Test func aThemeThatPublishesTheLookKeepsTheTokensInStepWithTheSetting() async {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        let published = state(glass: false)
        settings.set(.liquidGlass, for: InterfaceSettings.look)
        let theme = NotchTheme(settings: settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter(), lookState: published)
        #expect(published.isGlass, "from the first frame, not after the first change")
        settings.set(.classic, for: InterfaceSettings.look)
        #expect(await eventually { !published.isGlass })
        settings.set(.liquidGlass, for: InterfaceSettings.look)
        #expect(await eventually { published.isGlass })
        withExtendedLifetime(theme) {}
    }

    @Test func aThemeWithoutAStateLeavesTheAppsStateAlone() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        settings.set(.liquidGlass, for: InterfaceSettings.look)
        _ = NotchTheme(settings: settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter())
        #expect(!NotchLookState.shared.isGlass)
    }
}
