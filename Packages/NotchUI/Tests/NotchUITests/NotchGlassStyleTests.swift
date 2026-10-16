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

    func plan(_ surface: NotchSurface, _ style: NotchGlassStyle = .default, bubbles: [String] = [], open: Bool = false) -> NotchGlassPlan {
        NotchGlassPlan(surface: surface, bubbleIDs: bubbles, accent: accent, style: style, isOpen: open)
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
            #expect(closed.notch?.id == .notch)
            #expect(closed.tiles == nil)
            #expect(closed.panelHasGlass)
            #expect(closed.veil == 0)
            #expect(closed.shape == .slab)
        }
    }

    // MARK: the tiles

    @Test func withTilesTheNotchKeepsItsGlassShapeInEveryStateAndItIsNothingOnlyWhileOpen() throws {
        // The shape is there in every state (content is only drawn above glass when it is inside the view that carries it), and
        // its glass is the identity, which draws nothing, only while the notch is open and the tiles have come out of it.
        for clarity in NotchGlassClarity.allCases {
            let style = NotchGlassStyle(clarity: clarity, shape: .tiles)
            let closed = plan(glass, style, bubbles: ["a"], open: false)
            let open = plan(glass, style, bubbles: ["a"], open: true)
            #expect(closed.notch?.id == .notch && open.notch?.id == .notch)
            #expect(closed.notch?.glass == clarity.glass)
            #expect(closed.panelHasGlass)
            #expect(open.notch?.glass == Glass.identity)
            #expect(!open.panelHasGlass, "no glass of its own while the tiles are out")
        }
    }

    @Test func theTilesAreGlassInEveryStateAndSoAreTheSameViewsWhetherOrNotTheNotchIsOpen() throws {
        for open in [false, true] {
            let plan = plan(glass, NotchGlassStyle(shape: .tiles), open: open)
            let tiles = try #require(plan.tiles)
            #expect(tiles.isOpen == open)
            #expect(tiles.tabBar == .init(id: .tabBar, glass: Glass.regular), "open: \(open)")
            #expect(tiles.content == .init(id: .content, glass: Glass.regular), "open: \(open)")
            #expect(plan.shapes.map(\.id) == [.notch, .tabBar, .content])
            #expect(plan.shape == .tiles)
            #expect(plan.usesContainer, "they are in the notch's family, which is what lets them blend and split with its shape")
            #expect(plan.containerSpacing == NotchGlassPlan.containerSpacing)
        }
    }

    @Test func theSlabAndTheClassicLookHaveNoTilesAtAll() {
        for open in [false, true] {
            #expect(plan(glass, NotchGlassStyle(shape: .slab), open: open).tiles == nil)
            #expect(plan(.solid, NotchGlassStyle(shape: .tiles), open: open).tiles == nil)
        }
    }

    @Test func whenTheNotchIsNotOpenItsGlassAndTheBubblesAreTheSlabsAndTheTilesAreUnderIt() throws {
        let closed = plan(glass, NotchGlassStyle(clarity: .clear, shape: .tiles), bubbles: ["a"], open: false)
        let slab = plan(glass, NotchGlassStyle(clarity: .clear, shape: .slab), bubbles: ["a"], open: false)
        #expect(closed.notch == slab.notch, "collapsed notch: its own glass is the slab's")
        #expect(closed.bubbles == slab.bubbles, "bubbles: unchanged")
        #expect(closed.veil == 0)
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
            #expect(tiles?.tabBar.id == .tabBar && tiles?.content.id == .content, "the same names open or not, so the views keep them")
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

    @Test func theGlassIsDrawnActiveUnlessTheSwitchSaysOtherwise() {
        // The positive meaning, which `ScreenManager` hands every notch it makes: an inverted `!` there would flip the whole feature.
        func draws(_ value: Any?) -> Bool {
            let defaults = makeIsolatedDefaults()
            if let value { defaults.set(value, forKey: NotchGlassSupport.inactiveKey) }
            return NotchGlassSupport.drawsActiveGlass(defaults)
        }
        #expect(draws(nil))
        #expect(draws(0) && draws("no") && draws("") && draws(2))
        #expect(!draws(1) && !draws("true") && !draws(true) && !draws("yes"))
        #expect(NotchGlassSupport.drawsActiveGlass(makeIsolatedDefaults()) == !NotchGlassSupport.keepsGlassInactive(makeIsolatedDefaults()))
    }

    /// Every Swift source of the app and of its packages (not the tests, not what is built or checked out): the repository's `App`, and
    /// each `Sources` of `Packages/*` and `Packages/Modules/*`. A root that is not there (a copy of one package) is skipped.
    func sourceFiles() throws -> (all: [URL], notchUI: Int) {
        let packages = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let manager = FileManager.default
        var roots = [packages.appending(path: "NotchUI/Sources"), packages.deletingLastPathComponent().appending(path: "App")]
        for group in [packages, packages.appending(path: "Modules")] {
            for name in (try? manager.contentsOfDirectory(atPath: group.path)) ?? [] where name != "Modules" {
                roots.append(group.appending(path: "\(name)/Sources"))
            }
        }
        var files: [URL] = []
        var notchUI = 0
        for root in Set(roots) where manager.fileExists(atPath: root.path) {
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "swift" && !url.path.contains("/.build/") {
                files.append(url)
                if root.path.hasSuffix("NotchUI/Sources") { notchUI += 1 }
            }
        }
        return (files, notchUI)
    }

    @Test func noSourceFileOfTheAppNamesADebugGlassKeyButTheSupportOneOrBuildsOne() throws {
        // A guard on the source: a `debug.glass.*` key read from the defaults would be a spike switch again, in NotchUI, in the App or in
        // a module, and one built by interpolation would not even be found by name.
        let (files, notchUI) = try sourceFiles()
        #expect(notchUI > 30, "NotchUI's sources were found")
        let named = try Regex("debug\\.glass\\.([A-Za-z]+)")
        let interpolated = try Regex("debug\\.glass\\.\\\\\\(")
        var names: Set<String> = []
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in text.matches(of: named) { names.insert(String(match.output[1].substring ?? "")) }
            #expect(text.matches(of: interpolated).isEmpty, "\(url.lastPathComponent) builds a debug.glass key")
        }
        // The candidates for the clear glass (U3g) were keys for a while (`clearRecipe`, `clearTint`, `clearMaterial`); the chosen one is
        // the glass now, and none is read.
        #expect(names == ["inactive"], "\(names)")
        for removed in ["clearRecipe", "clearTint", "clearMaterial", "NotchClearRecipe"] {
            for url in files { #expect(!(try String(contentsOf: url, encoding: .utf8)).contains(removed), "\(url.lastPathComponent) names \(removed)") }
        }
        #expect(files.count > notchUI, "more than NotchUI was read (the App and the modules)")
    }

    @Test func theNotchsGlassIsNeverDrawnInALayerBehindItsContentAgain() throws {
        // Content is only drawn above glass when it is inside the view that carries the glass; a `background { … glassEffect … }`
        // layer put it under the glass and blurred the collapsed notch's text.
        let (files, _) = try sourceFiles()
        for url in files where url.path.contains("/NotchUI/Sources/") {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(!text.contains("notchGlassLayer"), "\(url.lastPathComponent)")
            #expect(text.matches(of: try Regex("background\\s*\\{[^}]*glassEffect")).isEmpty, "\(url.lastPathComponent)")
        }
    }
}
