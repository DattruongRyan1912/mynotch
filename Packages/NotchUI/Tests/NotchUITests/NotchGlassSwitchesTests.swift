import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// The debug switches of the glass look (U3c): plain `UserDefaults` keys, today's behaviour when one is missing or not understood,
/// and what each one does to the glass plan. Nothing here draws: glass is composited by the window server, so a test reads the
/// plan the root view and the bubbles draw from.
@Suite struct NotchGlassSwitchesTests {
    let accent = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.9)
    let glass = NotchSurface.liquidGlass(tinted: false)
    let tinted = NotchSurface.liquidGlass(tinted: true)

    func read(_ values: [String: Any]) -> NotchGlassSwitches {
        let defaults = makeIsolatedDefaults()
        for (key, value) in values { defaults.set(value, forKey: key) }
        return NotchGlassSwitches(reading: defaults)
    }

    func plan(_ surface: NotchSurface, _ switches: NotchGlassSwitches, bubbles: [String] = [], open: Bool = false) -> NotchGlassPlan {
        NotchGlassPlan(surface: surface, bubbleIDs: bubbles, accent: accent, switches: switches, isOpen: open)
    }

    // MARK: reading the keys

    @Test func noKeyIsTodaysBehaviourInEverySwitch() {
        let switches = NotchGlassSwitches(reading: makeIsolatedDefaults())
        #expect(switches == .default)
        #expect(switches.variant == .regular)
        #expect(switches.panel == .slab)
        #expect(switches.dim == 0)
        #expect(switches.scheme == .system)
        #expect(switches.sample == false)
        #expect(switches.selected == .tint)
    }

    @Test func theKeysAreTheOnesTheBriefNames() {
        #expect(NotchGlassSwitches.Key.all == [
            "debug.glass.variant", "debug.glass.panel", "debug.glass.dim", "debug.glass.scheme", "debug.glass.sample", "debug.glass.selected",
        ])
    }

    @Test func theSwitchesOfTheFirstSpikeThatWentAreNotReadAnyMore() {
        // The AppKit host and the glass cards inside the panel's glass were dropped; a key left from that spike changes nothing.
        #expect(read(["debug.glass.host": "appkit", "debug.glass.cards": "glass"]) == .default)
    }

    @Test func everyNameIsReadFromItsKey() {
        let switches = read([
            "debug.glass.variant": "clear", "debug.glass.panel": "tiles", "debug.glass.dim": 0.15, "debug.glass.scheme": "dark",
            "debug.glass.sample": 1, "debug.glass.selected": "white",
        ])
        #expect(switches == NotchGlassSwitches(variant: .clear, panel: .tiles, dim: 0.15, scheme: .dark, sample: true, selected: .white))
        // And each one alone leaves the others as they were.
        #expect(read(["debug.glass.variant": "clear"]) == NotchGlassSwitches(variant: .clear))
        #expect(read(["debug.glass.panel": "tiles"]) == NotchGlassSwitches(panel: .tiles))
        #expect(read(["debug.glass.panel": "slab"]) == NotchGlassSwitches(panel: .slab))
        #expect(read(["debug.glass.scheme": "dark"]) == NotchGlassSwitches(scheme: .dark))
        #expect(read(["debug.glass.selected": "white"]) == NotchGlassSwitches(selected: .white))
        #expect(read(["debug.glass.sample": 1]) == NotchGlassSwitches(sample: true))
        #expect(read(["debug.glass.dim": 0.2]) == NotchGlassSwitches(dim: 0.2))
    }

    @Test func theNamesDoNotCareAboutCaseOrSpaces() {
        #expect(read(["debug.glass.variant": " Clear "]).variant == .clear)
        #expect(read(["debug.glass.panel": "Tiles"]).panel == .tiles)
        #expect(read(["debug.glass.scheme": "DARK"]).scheme == .dark)
    }

    @Test func aMissingUnknownOrWronglyTypedValueIsTodaysBehaviour() {
        let wrong: [String: Any] = [
            "debug.glass.variant": "frosted", "debug.glass.panel": "grid", "debug.glass.dim": "a lot", "debug.glass.scheme": "light",
            "debug.glass.sample": "maybe", "debug.glass.selected": "red",
        ]
        #expect(read(wrong) == .default)
        // Numbers where names go, and names where a number goes.
        #expect(read(["debug.glass.variant": 1, "debug.glass.panel": true, "debug.glass.selected": 0.5]) == .default)
        #expect(read(["debug.glass.dim": ["0.2"], "debug.glass.sample": ["1"]]) == .default)
        // An empty string is not a name either.
        #expect(read(["debug.glass.variant": "", "debug.glass.dim": "", "debug.glass.panel": ""]) == .default)
    }

    @Test func aPanelThatIsNotOneOfTheTwoFallsBackToTheSlab() {
        for value: Any in ["slabs", "tile", "none", "", " ", 1, 0, true, ["tiles"]] {
            #expect(read(["debug.glass.panel": value]).panel == .slab, "\(value)")
        }
    }

    @Test func aKeyThatIsNotOursChangesNothing() {
        #expect(read(["interface.look": "clear", "debug.glass": "clear", "debug.variant": "clear", "debug.panel": "tiles"]) == .default)
    }

    // MARK: dim

    @Test func dimTakesANumberOrAStringAsDefaultsWritePutsThem() {
        // `defaults write … -float 0.15` is a number; a bare `0.15` (or `-string`) is a string.
        #expect(read(["debug.glass.dim": 0.15]).dim == 0.15)
        #expect(read(["debug.glass.dim": Float(0.25)]).dim == Double(Float(0.25)))
        #expect(read(["debug.glass.dim": "0.15"]).dim == 0.15)
        #expect(read(["debug.glass.dim": " 0.3 "]).dim == 0.3)
        #expect(read(["debug.glass.dim": 0]).dim == 0)
    }

    @Test func dimIsHeldToZeroThroughPointFour() {
        #expect(NotchGlassSwitches.dimRange == 0...0.4)
        #expect(read(["debug.glass.dim": 0.4]).dim == 0.4)
        #expect(read(["debug.glass.dim": 0.9]).dim == 0.4)
        #expect(read(["debug.glass.dim": "5"]).dim == 0.4)
        #expect(read(["debug.glass.dim": -0.2]).dim == 0)
        #expect(read(["debug.glass.dim": "-1"]).dim == 0)
        #expect(NotchGlassSwitches(dim: 7).dim == 0.4)
    }

    @Test func dimThatIsNotANumberIsZero() {
        #expect(read(["debug.glass.dim": "nan"]).dim == 0)
        #expect(read(["debug.glass.dim": "inf"]).dim == 0)
        #expect(NotchGlassSwitches(dim: .nan).dim == 0)
        #expect(NotchGlassSwitches(dim: .infinity).dim == 0)
    }

    // MARK: sample

    @Test func sampleIsOnForOneTrueOrYesAndOffForEverythingElse() {
        for on: Any in [1, true, "1", "true", "TRUE", "yes", Int8(1)] {
            #expect(read(["debug.glass.sample": on]).sample, "\(on)")
        }
        for off: Any in [0, false, "0", "false", "no", "", 2, -1, "2", "on"] {
            #expect(!read(["debug.glass.sample": off]).sample, "\(off)")
        }
    }

    // MARK: what the switches do to the plan

    @Test func clearGlassIsTheNotchsAndTheBubblesVariant() {
        let plan = plan(glass, NotchGlassSwitches(variant: .clear), bubbles: ["a", "b"])
        #expect(plan.notch?.glass == Glass.clear)
        #expect(plan.notch?.glass != Glass.regular)
        #expect(plan.bubbles.allSatisfy { $0.glass == Glass.clear.interactive() })
        #expect(plan.bubbles.allSatisfy { $0.glass != Glass.regular.interactive() })
    }

    @Test func regularGlassIsWhatItAlwaysWasAndTheNotchIsNeverInteractive() {
        let plan = plan(glass, NotchGlassSwitches(variant: .regular), bubbles: ["a"])
        #expect(plan == self.plan(glass, .default, bubbles: ["a"]))
        #expect(plan == NotchGlassPlan(surface: glass, bubbleIDs: ["a"], accent: accent), "the plan without switches is today's")
        #expect(plan.notch?.glass == Glass.regular)
        #expect(plan.notch?.glass != Glass.regular.interactive())
        #expect(plan.bubbles.first?.glass == Glass.regular.interactive())
        #expect(plan.tiles == nil)
        #expect(plan.panel == .slab)
    }

    @Test func theTintFollowsTheAccentOnClearGlassToo() {
        let hint = accent.opacity(NotchTokens.glassTintOpacity)
        let plan = plan(tinted, NotchGlassSwitches(variant: .clear), bubbles: ["a"])
        #expect(plan.notch?.glass == Glass.clear.tint(hint))
        #expect(plan.notch?.glass != Glass.clear)
        #expect(plan.bubbles.first?.glass == Glass.clear.tint(hint).interactive())
    }

    @Test func theDimAndTheSchemeAreCarriedForTheViewsToDrawAndTheSchemeIsOnlyForTheContent() {
        let plan = plan(glass, NotchGlassSwitches(dim: 0.15, scheme: .dark))
        #expect(plan.backdropOpacity == 0.15, "the black layer inside the notch's shape")
        #expect(plan.contentScheme == .dark)
        #expect(self.plan(glass, .default).backdropOpacity == 0)
        #expect(self.plan(glass, .default).contentScheme == nil, "the system's scheme: nothing is forced")
        #expect(self.plan(glass, NotchGlassSwitches(scheme: .system)).contentScheme == nil)
    }

    // MARK: the usual panel

    @Test func theSlabIsOneShapeWhetherTheNotchIsOpenOrNot() {
        for switches in [NotchGlassSwitches.default, NotchGlassSwitches(variant: .clear, dim: 0.2, scheme: .dark, sample: true, selected: .white)] {
            let closed = plan(glass, switches, bubbles: ["a"], open: false)
            let open = plan(glass, switches, bubbles: ["a"], open: true)
            #expect(closed == open, "the slab does not depend on the state")
            #expect(open.notch?.id == .notch)
            #expect(open.tiles == nil)
            #expect(!open.cardsAreOnTheDesktop)
            #expect(open.backdropOpacity == switches.dim)
        }
    }

    // MARK: the tiles

    @Test func withTilesThePanelOfTheOpenNotchHasNoGlassAndTheTabBarAndTheContentHaveOneShapeEach() throws {
        let plan = plan(glass, NotchGlassSwitches(panel: .tiles), open: true)
        #expect(plan.panel == .tiles)
        #expect(plan.notch == nil, "no glass on the panel itself")
        let tiles = try #require(plan.tiles)
        #expect(tiles.isOpen)
        #expect(tiles.tabBar == .init(id: .tabBar, glass: Glass.regular))
        #expect(tiles.content == .init(id: .content, glass: Glass.regular))
        #expect(plan.shapes.map(\.id) == [.tabBar, .content], "one shape for the tab bar and one for the content, nothing else")
        #expect(plan.cardsAreOnTheDesktop)
        #expect(plan.usesContainer, "they are in the notch's family, which is what lets them morph with its shape")
        #expect(plan.containerSpacing == NotchGlassPlan.containerSpacing)
    }

    @Test func theTilesTakeTheVariantAndTheTintLikeTheNotchDoes() {
        let clear = plan(glass, NotchGlassSwitches(variant: .clear, panel: .tiles), open: true)
        #expect(clear.tiles?.tabBar.glass == Glass.clear)
        #expect(clear.tiles?.content.glass == Glass.clear)
        let regular = plan(glass, NotchGlassSwitches(variant: .regular, panel: .tiles), open: true)
        #expect(regular.tiles?.tabBar.glass == Glass.regular)
        #expect(regular.tiles?.content.glass == Glass.regular)
        let hint = accent.opacity(NotchTokens.glassTintOpacity)
        let hinted = plan(tinted, NotchGlassSwitches(variant: .clear, panel: .tiles), open: true)
        #expect(hinted.tiles?.tabBar.glass == Glass.clear.tint(hint))
        #expect(hinted.tiles?.content.glass == Glass.clear.tint(hint))
        #expect(clear.tiles?.tabBar.glass != Glass.clear.interactive(), "a tile is a surface, not a control")
    }

    @Test func theTilesAreNamedInTheNotchsNamespaceWithNamesOfTheirOwn() {
        let ids = [NotchGlassID.notch, .tabBar, .content, .bubble("a")]
        #expect(Set(ids).count == 4)
        let open = plan(glass, NotchGlassSwitches(panel: .tiles), bubbles: ["a"], open: true)
        let closed = plan(glass, NotchGlassSwitches(panel: .tiles), bubbles: ["a"], open: false)
        #expect(open.tiles?.tabBar.id == .tabBar && open.tiles?.content.id == .content)
        #expect(closed.tiles?.tabBar.id == .tabBar && closed.tiles?.content.id == .content, "the same names, so the views keep them")
        #expect(closed.notch?.id == .notch, "the notch's glass is the one that goes, and that is what morphs into the tiles")
    }

    @Test func withTilesTheClosedNotchIsTheSlabItWasAndItsTilesDrawNothing() {
        let closed = plan(glass, NotchGlassSwitches(variant: .clear, panel: .tiles, dim: 0.2), bubbles: ["a"], open: false)
        let slab = plan(glass, NotchGlassSwitches(variant: .clear, panel: .slab, dim: 0.2), bubbles: ["a"], open: false)
        #expect(closed.notch == slab.notch, "collapsed notch: unchanged")
        #expect(closed.bubbles == slab.bubbles, "bubbles: unchanged")
        #expect(closed.backdropOpacity == slab.backdropOpacity)
        #expect(closed.tiles?.isOpen == false)
        #expect(closed.tiles?.tabBar.glass == Glass.identity, "a tab kept alive under a toast has no glass")
        #expect(closed.tiles?.content.glass == Glass.identity)
        #expect(closed.tiles?.dim == 0)
        #expect(!closed.cardsAreOnTheDesktop)
    }

    @Test func theDimGoesInsideEachTileAndTheOpenPanelOnlyKeepsAVeilTooFaintToSee() {
        let open = plan(glass, NotchGlassSwitches(variant: .clear, panel: .tiles, dim: 0.25), open: true)
        #expect(open.tiles?.dim == 0.25, "in each tile, above its glass")
        #expect(open.backdropOpacity == NotchGlassPlan.hitOpacity, "not a fill over the panel: the desktop shows between the tiles")
        #expect(NotchGlassPlan.hitOpacity > 0, "enough that a click in a gap stays in the window")
        #expect(NotchGlassPlan.hitOpacity < 3.0 / 255, "under three levels of 255")
        let without = plan(glass, NotchGlassSwitches(panel: .tiles), open: true)
        #expect(without.tiles?.dim == 0)
        #expect(without.backdropOpacity == NotchGlassPlan.hitOpacity)
    }

    @Test func tilesAreFartherApartThanTheyBlendAndTheirRadiusIsConcentric() {
        #expect(NotchGlassPlan.tileGap > NotchGlassPlan.containerSpacing, "so two tiles do not melt into each other")
        #expect(NotchGlassPlan.tileGap == NotchSampleStrip.bottomGap)
        #expect(NotchGlassPlan.tilePadding > 0 && NotchGlassPlan.tabBarInset.width > 0 && NotchGlassPlan.tabBarInset.height > 0)
        let geometry = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
        let outer = geometry.cornerRadii(for: .open(nil)).bottom
        #expect(NotchCardPlan.concentricRadius(outer: outer, inset: NotchTokens.padding) == 10, "24 - 14")
    }

    @Test func theBubblesDoNotChangeWithThePanel() {
        for open in [false, true] {
            let slab = plan(glass, NotchGlassSwitches(panel: .slab), bubbles: ["a", "b"], open: open)
            let tiles = plan(glass, NotchGlassSwitches(panel: .tiles), bubbles: ["a", "b"], open: open)
            #expect(slab.bubbles == tiles.bubbles)
        }
    }

    // MARK: every switch is a no-op unless the notch is Liquid Glass

    @Test func theClassicNotchIsUntouchedWhateverTheSwitchesSay() {
        let everything = NotchGlassSwitches(variant: .clear, panel: .tiles, dim: 0.4, scheme: .dark, sample: true, selected: .white)
        for surface in [NotchSurface.solid, .material] {
            for open in [false, true] {
                let plan = plan(surface, everything, bubbles: ["a", "b"], open: open)
                #expect(plan == .none, "\(surface) open: \(open)")
                #expect(plan.notch == nil && plan.tiles == nil && plan.bubbles.isEmpty)
                #expect(plan.backdropOpacity == 0)
                #expect(plan.contentScheme == nil)
                #expect(!plan.usesContainer)
                #expect(!plan.cardsAreOnTheDesktop)
            }
        }
    }
}
