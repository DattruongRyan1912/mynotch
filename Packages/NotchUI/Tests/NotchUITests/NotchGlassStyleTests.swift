import MyNotchCore
import MyNotchTestSupport
import Observation
import SwiftUI
import Testing
@testable import NotchUI

/// The two settings of the Liquid Glass (`interface.glassClarity`, `interface.glassShape`), what they do to the glass plan, and the
/// one key of it that is not a setting (`NotchGlassSupport`). Nothing here draws: glass is composited by the window server, so a test
/// reads the plan the root view and the bubbles draw from.
@Suite struct NotchGlassStyleTests {
    let accent = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.9)
    let glass = NotchSurface.liquidGlass(tinted: false)
    let tinted = NotchSurface.liquidGlass(tinted: true)

    func plan(
        _ surface: NotchSurface, _ style: NotchGlassStyle = .default, bubbles: [String] = [], open: Bool = false, settled: Bool = true
    ) -> NotchGlassPlan {
        NotchGlassPlan(surface: surface, bubbleIDs: bubbles, accent: accent, style: style, isOpen: open, tilesSettled: settled)
    }

    // MARK: the settings

    @Test func theDefaultsAreBalancedAndOnePiece() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        #expect(settings.value(InterfaceSettings.glassClarity) == .balanced)
        #expect(settings.value(InterfaceSettings.glassShape) == .slab)
        #expect(NotchGlassStyle.default == NotchGlassStyle(clarity: .balanced, shape: .slab))
        #expect(InterfaceSettings.glassClarity.name == "interface.glassClarity")
        #expect(InterfaceSettings.glassShape.name == "interface.glassShape")
    }

    @Test func eachChoiceIsStoredByItsNameAndReadBack() throws {
        let defaults = makeIsolatedDefaults()
        let settings = SettingsStore(defaults: defaults)
        for clarity in NotchGlassClarity.allCases {
            settings.set(clarity, for: InterfaceSettings.glassClarity)
            #expect(settings.value(InterfaceSettings.glassClarity) == clarity)
            let stored = try #require(defaults.data(forKey: "interface.glassClarity"))
            #expect(String(decoding: stored, as: UTF8.self) == "\"\(clarity.rawValue)\"")
        }
        for shape in NotchGlassShape.allCases {
            settings.set(shape, for: InterfaceSettings.glassShape)
            #expect(settings.value(InterfaceSettings.glassShape) == shape)
            let stored = try #require(defaults.data(forKey: "interface.glassShape"))
            #expect(String(decoding: stored, as: UTF8.self) == "\"\(shape.rawValue)\"")
        }
        #expect(NotchGlassClarity.allCases.map(\.rawValue) == ["balanced", "clear"])
        #expect(NotchGlassShape.allCases.map(\.rawValue) == ["slab", "tiles"])
    }

    @Test func aValueThatIsNotOneOfTheNamesIsTheDefault() {
        let defaults = makeIsolatedDefaults()
        let settings = SettingsStore(defaults: defaults)
        for text in ["\"frosted\"", "\"\"", "\"Clear\"", "3", "true", "null", "[\"clear\"]", "not json at all"] {
            defaults.set(Data(text.utf8), forKey: "interface.glassClarity")
            defaults.set(Data(text.utf8), forKey: "interface.glassShape")
            #expect(settings.value(InterfaceSettings.glassClarity) == .balanced, "\(text)")
            #expect(settings.value(InterfaceSettings.glassShape) == .slab, "\(text)")
        }
        // Not data at all, as a bare `defaults write` would leave it.
        defaults.set("clear", forKey: "interface.glassClarity")
        defaults.set("tiles", forKey: "interface.glassShape")
        #expect(settings.value(InterfaceSettings.glassClarity) == .balanced)
        #expect(settings.value(InterfaceSettings.glassShape) == .slab)
    }

    @Test func theChoicesLeaveTheOtherSettingsAlone() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        settings.set(.clear, for: InterfaceSettings.glassClarity)
        settings.set(.tiles, for: InterfaceSettings.glassShape)
        #expect(settings.value(InterfaceSettings.look) == .classic)
        #expect(settings.value(InterfaceSettings.glassTint) == false)
        #expect(settings.value(InterfaceSettings.glass) == false)
        settings.reset(InterfaceSettings.glassClarity)
        settings.reset(InterfaceSettings.glassShape)
        #expect(settings.value(InterfaceSettings.glassClarity) == .balanced)
        #expect(settings.value(InterfaceSettings.glassShape) == .slab)
    }

    // MARK: live

    func theme(_ settings: SettingsStore) -> NotchTheme {
        NotchTheme(settings: settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter())
    }

    @Test func theThemeFollowsTheSettingsWithoutARelaunch() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        let theme = theme(settings)
        #expect(theme.glassStyle == .default)
        settings.set(.clear, for: InterfaceSettings.glassClarity)
        #expect(theme.glassClarity == .clear)
        #expect(theme.glassStyle == NotchGlassStyle(clarity: .clear, shape: .slab))
        settings.set(.tiles, for: InterfaceSettings.glassShape)
        #expect(theme.glassShape == .tiles)
        #expect(theme.glassStyle == NotchGlassStyle(clarity: .clear, shape: .tiles))
        settings.set(.balanced, for: InterfaceSettings.glassClarity)
        #expect(theme.glassStyle == NotchGlassStyle(clarity: .balanced, shape: .tiles))
    }

    final class Told: @unchecked Sendable {
        nonisolated(unsafe) var count = 0
    }

    @Test func aViewThatReadTheStyleIsToldWhenEitherChoiceChanges() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        let theme = theme(settings)
        for change in [{ settings.set(.clear, for: InterfaceSettings.glassClarity) }, { settings.set(.tiles, for: InterfaceSettings.glassShape) }] as [() -> Void] {
            let told = Told()
            withObservationTracking { _ = theme.glassStyle } onChange: { told.count += 1 }
            change()
            #expect(told.count == 1, "a body that reads `glassStyle` is redrawn")
        }
    }

    @Test func thePlanFollowsTheStyleItIsGivenAndSoTheOpenNotchChangesWithoutARelaunch() {
        // What the root view does on a change: it asks for the plan again with the style the theme now gives.
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        let theme = theme(settings)
        func current() -> NotchGlassPlan { plan(glass, theme.glassStyle, open: true) }
        #expect(current().notch?.glass == Glass.regular)
        #expect(current().tiles == nil)
        settings.set(.clear, for: InterfaceSettings.glassClarity)
        #expect(current().notch?.glass == Glass.clear)
        settings.set(.tiles, for: InterfaceSettings.glassShape)
        #expect(current().tiles?.content.glass == Glass.clear)
        #expect(!current().panelHasGlass)
        settings.set(.slab, for: InterfaceSettings.glassShape)
        #expect(current().tiles == nil && current().panelHasGlass)
    }

    // MARK: clarity

    @Test func balancedIsTheRegularGlassAndClearIsTheClearOneForTheNotchAndTheBubbles() {
        let balanced = plan(glass, NotchGlassStyle(clarity: .balanced), bubbles: ["a", "b"])
        #expect(balanced.notch?.glass == Glass.regular)
        #expect(balanced.notch?.glass != Glass.regular.interactive(), "the notch is a surface, not a control")
        #expect(balanced.bubbles.allSatisfy { $0.glass == Glass.regular.interactive() })
        #expect(balanced == plan(glass, .default, bubbles: ["a", "b"]))
        #expect(balanced == NotchGlassPlan(surface: glass, bubbleIDs: ["a", "b"], accent: accent), "the plan with no style is today's")

        let clear = plan(glass, NotchGlassStyle(clarity: .clear), bubbles: ["a", "b"])
        #expect(clear.notch?.glass == Glass.clear)
        #expect(clear.notch?.glass != Glass.regular)
        #expect(clear.bubbles.allSatisfy { $0.glass == Glass.clear.interactive() })
        #expect(clear.bubbles.allSatisfy { $0.glass != Glass.regular.interactive() })
    }

    @Test func theTintFollowsTheAccentOnBothClarities() {
        let hint = accent.opacity(NotchTokens.glassTintOpacity)
        let balanced = plan(tinted, NotchGlassStyle(clarity: .balanced), bubbles: ["a"])
        #expect(balanced.notch?.glass == Glass.regular.tint(hint))
        let clear = plan(tinted, NotchGlassStyle(clarity: .clear), bubbles: ["a"])
        #expect(clear.notch?.glass == Glass.clear.tint(hint))
        #expect(clear.notch?.glass != Glass.clear)
        #expect(clear.bubbles.first?.glass == Glass.clear.tint(hint).interactive())
    }

    // MARK: the slab

    @Test func theSlabIsOneShapeWhateverTheNotchIsDoing() {
        for clarity in NotchGlassClarity.allCases {
            let style = NotchGlassStyle(clarity: clarity, shape: .slab)
            let closed = plan(glass, style, bubbles: ["a"], open: false)
            #expect(closed == plan(glass, style, bubbles: ["a"], open: true), "the slab does not depend on the state")
            #expect(closed == plan(glass, style, bubbles: ["a"], open: true, settled: false))
            #expect(closed.notch?.id == .notch)
            #expect(closed.tiles == nil)
            #expect(closed.panelHasGlass)
            #expect(closed.veil == 0)
            #expect(closed.shape == .slab)
        }
    }

    // MARK: the tiles

    @Test func withTilesTheOpenNotchHasNoGlassOfItsOwnOnceSettledAndOneShapeEachForTheTabBarAndTheContent() throws {
        let plan = plan(glass, NotchGlassStyle(shape: .tiles), open: true, settled: true)
        #expect(plan.shape == .tiles)
        #expect(!plan.panelHasGlass, "no glass on the panel itself")
        #expect(plan.notch?.glass == Glass.identity)
        let tiles = try #require(plan.tiles)
        #expect(tiles.isShown)
        #expect(tiles.tabBar == .init(id: .tabBar, glass: Glass.regular))
        #expect(tiles.content == .init(id: .content, glass: Glass.regular))
        #expect(plan.shapes.map(\.id) == [.notch, .tabBar, .content])
        #expect(plan.usesContainer, "they are in the notch's family, which is what lets them morph with its shape")
        #expect(plan.containerSpacing == NotchGlassPlan.containerSpacing)
    }

    @Test func whileTheOpenNotchGrowsItKeepsItsOwnGlassSoThereIsNoStretchWithNoGlassAtAll() throws {
        let growing = plan(glass, NotchGlassStyle(shape: .tiles), open: true, settled: false)
        #expect(growing.panelHasGlass)
        #expect(growing.notch?.glass == Glass.regular)
        let tiles = try #require(growing.tiles)
        #expect(!tiles.isShown)
        #expect(tiles.tabBar.glass == Glass.identity && tiles.content.glass == Glass.identity)
        // At every moment of the opening one of the two is real glass: the notch's, then the tiles'.
        let settled = plan(glass, NotchGlassStyle(shape: .tiles), open: true, settled: true)
        #expect(growing.panelHasGlass != (settled.tiles?.isShown == false))
        #expect(growing.panelHasGlass || settled.tiles?.isShown == true)
        #expect(NotchGlassPlan.tilesDelay >= .milliseconds(200) && NotchGlassPlan.tilesDelay <= .milliseconds(500), "about the notch's spring")
        #expect(growing.veil == NotchGlassPlan.hitOpacity, "the gaps are part of the window from the first moment")
    }

    @Test func whenTheNotchIsNotOpenTheNotchsGlassIsBackAndTheTilesDrawNothing() throws {
        let closed = plan(glass, NotchGlassStyle(clarity: .clear, shape: .tiles), bubbles: ["a"], open: false)
        let slab = plan(glass, NotchGlassStyle(clarity: .clear, shape: .slab), bubbles: ["a"], open: false)
        #expect(closed.notch == slab.notch, "collapsed notch: unchanged")
        #expect(closed.bubbles == slab.bubbles, "bubbles: unchanged")
        #expect(closed.veil == 0)
        let tiles = try #require(closed.tiles)
        #expect(!tiles.isShown)
        #expect(tiles.tabBar.glass == Glass.identity, "a tab kept alive under a toast has no glass")
        #expect(tiles.content.glass == Glass.identity)
    }

    @Test func theTilesTakeTheClarityAndTheTintLikeTheNotchDoes() {
        let clear = plan(glass, NotchGlassStyle(clarity: .clear, shape: .tiles), open: true)
        #expect(clear.tiles?.tabBar.glass == Glass.clear)
        #expect(clear.tiles?.content.glass == Glass.clear)
        let balanced = plan(glass, NotchGlassStyle(clarity: .balanced, shape: .tiles), open: true)
        #expect(balanced.tiles?.tabBar.glass == Glass.regular)
        let hint = accent.opacity(NotchTokens.glassTintOpacity)
        let hinted = plan(tinted, NotchGlassStyle(clarity: .clear, shape: .tiles), open: true)
        #expect(hinted.tiles?.tabBar.glass == Glass.clear.tint(hint))
        #expect(hinted.tiles?.content.glass == Glass.clear.tint(hint))
        #expect(clear.tiles?.tabBar.glass != Glass.clear.interactive(), "a tile is a surface, not a control")
    }

    @Test func theTilesAreNamedInTheNotchsNamespaceWithNamesOfTheirOwn() {
        let ids = [NotchGlassID.notch, .tabBar, .content, .bubble("a")]
        #expect(Set(ids).count == 4)
        for open in [false, true] {
            let tiles = plan(glass, NotchGlassStyle(shape: .tiles), bubbles: ["a"], open: open).tiles
            #expect(tiles?.tabBar.id == .tabBar && tiles?.content.id == .content, "the same names whether shown or not, so the views keep them")
        }
    }

    @Test func theVeilIsTooFaintToSeeAndOnlyThereWhileTheTilesNotchIsOpen() {
        #expect(NotchGlassPlan.hitOpacity > 0, "enough that a click in a gap stays in the window")
        #expect(NotchGlassPlan.hitOpacity < 3.0 / 255, "under three levels of 255")
        #expect(plan(glass, NotchGlassStyle(shape: .tiles), open: true).veil == NotchGlassPlan.hitOpacity)
        #expect(plan(glass, NotchGlassStyle(shape: .tiles), open: false).veil == 0)
        #expect(plan(glass, NotchGlassStyle(shape: .slab), open: true).veil == 0)
    }

    @Test func tilesAreFartherApartThanTheyBlendAndTheirRadiusIsConcentric() {
        #expect(NotchGlassPlan.tileGap > NotchGlassPlan.containerSpacing, "so two tiles do not melt into each other")
        #expect(NotchGlassPlan.tilePadding > 0 && NotchGlassPlan.tabBarInset.width > 0 && NotchGlassPlan.tabBarInset.height > 0)
        let geometry = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
        let outer = geometry.cornerRadii(for: .open(nil)).bottom
        #expect(NotchGlassPlan.concentricRadius(outer: outer, inset: NotchTokens.padding) == 10, "24 - 14")
        #expect(NotchGlassPlan.concentricRadius(outer: 6, inset: 14) == 0, "never negative")
    }

    @Test func theBubblesDoNotChangeWithTheShape() {
        for open in [false, true] {
            #expect(
                plan(glass, NotchGlassStyle(shape: .slab), bubbles: ["a", "b"], open: open).bubbles
                    == plan(glass, NotchGlassStyle(shape: .tiles), bubbles: ["a", "b"], open: open).bubbles
            )
        }
    }

    // MARK: the classic look

    @Test func theClassicNotchIsUntouchedWhateverTheStyleIs() {
        for style in [NotchGlassStyle(clarity: .clear, shape: .tiles), NotchGlassStyle(clarity: .balanced, shape: .tiles), NotchGlassStyle(clarity: .clear, shape: .slab)] {
            for surface in [NotchSurface.solid, .material] {
                for open in [false, true] {
                    let plan = plan(surface, style, bubbles: ["a", "b"], open: open)
                    #expect(plan == .none, "\(surface) \(style) open: \(open)")
                    #expect(plan.notch == nil && plan.tiles == nil && plan.bubbles.isEmpty)
                    #expect(plan.veil == 0)
                    #expect(!plan.usesContainer)
                }
            }
        }
    }

    // MARK: the one key that is left

    func supportKey(_ value: Any?) -> Bool {
        let defaults = makeIsolatedDefaults()
        if let value { defaults.set(value, forKey: NotchGlassSupport.inactiveKey) }
        return NotchGlassSupport.keepsGlassInactive(defaults)
    }

    @Test func theSupportSwitchIsOffUnlessTheKeyIsOneTrueOrYes() {
        #expect(NotchGlassSupport.inactiveKey == "debug.glass.inactive")
        #expect(!supportKey(nil))
        for on: Any in [1, true, "1", "true", "TRUE", " yes "] { #expect(supportKey(on), "\(on)") }
        for off: Any in [0, false, "0", "false", "no", "", 2, -1, "2", "on", ["1"]] { #expect(!supportKey(off), "\(off)") }
    }

    @Test func noSpikeSwitchIsReadAnyMore() {
        // Every key of the earlier spikes, left in the defaults, changes nothing: only the support key is read.
        let defaults = makeIsolatedDefaults()
        for key in ["variant", "host", "dim", "scheme", "sample", "cards", "selected", "panel", "active"] {
            defaults.set("1", forKey: "debug.glass.\(key)")
            defaults.set(1, forKey: "debug.glass.\(key)")
        }
        #expect(!NotchGlassSupport.keepsGlassInactive(defaults))
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.value(InterfaceSettings.glassClarity) == .balanced)
        #expect(settings.value(InterfaceSettings.glassShape) == .slab)
    }

    @Test func noSourceFileNamesADebugGlassKeyButTheSupportOne() throws {
        // A guard on the source: a `debug.glass.*` key read from the defaults would be a spike switch again.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appending(path: "Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let pattern = try Regex("debug\\.glass\\.([A-Za-z]+)")
        var names: Set<String> = []
        var count = 0
        for case let url as URL in files where url.pathExtension == "swift" {
            count += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in text.matches(of: pattern) { names.insert(String(match.output[1].substring ?? "")) }
        }
        #expect(count > 30, "the sources were found")
        #expect(names == ["inactive"], "\(names)")
    }
}
