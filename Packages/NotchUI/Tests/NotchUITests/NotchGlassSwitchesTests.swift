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

    func plan(_ surface: NotchSurface, _ switches: NotchGlassSwitches, bubbles: [String] = []) -> NotchGlassPlan {
        NotchGlassPlan(surface: surface, bubbleIDs: bubbles, accent: accent, switches: switches)
    }

    // MARK: reading the keys

    @Test func noKeyIsTodaysBehaviourInEverySwitch() {
        let switches = NotchGlassSwitches(reading: makeIsolatedDefaults())
        #expect(switches == .default)
        #expect(switches.variant == .regular)
        #expect(switches.host == .swiftui)
        #expect(switches.dim == 0)
        #expect(switches.scheme == .system)
        #expect(switches.sample == false)
        #expect(switches.cards == .fill)
        #expect(switches.selected == .tint)
    }

    @Test func theKeysAreTheOnesTheBriefNames() {
        #expect(NotchGlassSwitches.Key.all == [
            "debug.glass.variant", "debug.glass.host", "debug.glass.dim", "debug.glass.scheme", "debug.glass.sample", "debug.glass.cards",
            "debug.glass.selected",
        ])
    }

    @Test func everyNameIsReadFromItsKey() {
        let switches = read([
            "debug.glass.variant": "clear", "debug.glass.host": "appkit", "debug.glass.dim": 0.15, "debug.glass.scheme": "dark",
            "debug.glass.sample": 1, "debug.glass.cards": "glass", "debug.glass.selected": "white",
        ])
        #expect(switches == NotchGlassSwitches(
            variant: .clear, host: .appkit, dim: 0.15, scheme: .dark, sample: true, cards: .glass, selected: .white
        ))
        // And each one alone leaves the others as they were.
        #expect(read(["debug.glass.variant": "clear"]) == NotchGlassSwitches(variant: .clear))
        #expect(read(["debug.glass.host": "appkit"]) == NotchGlassSwitches(host: .appkit))
        #expect(read(["debug.glass.scheme": "dark"]) == NotchGlassSwitches(scheme: .dark))
        #expect(read(["debug.glass.cards": "glass"]) == NotchGlassSwitches(cards: .glass))
        #expect(read(["debug.glass.selected": "white"]) == NotchGlassSwitches(selected: .white))
        #expect(read(["debug.glass.sample": 1]) == NotchGlassSwitches(sample: true))
        #expect(read(["debug.glass.dim": 0.2]) == NotchGlassSwitches(dim: 0.2))
    }

    @Test func theNamesDoNotCareAboutCaseOrSpaces() {
        #expect(read(["debug.glass.variant": " Clear "]).variant == .clear)
        #expect(read(["debug.glass.host": "AppKit"]).host == .appkit)
        #expect(read(["debug.glass.scheme": "DARK"]).scheme == .dark)
    }

    @Test func aMissingUnknownOrWronglyTypedValueIsTodaysBehaviour() {
        let wrong: [String: Any] = [
            "debug.glass.variant": "frosted", "debug.glass.host": "metal", "debug.glass.dim": "a lot", "debug.glass.scheme": "light",
            "debug.glass.sample": "maybe", "debug.glass.cards": "tiles", "debug.glass.selected": "red",
        ]
        #expect(read(wrong) == .default)
        // Numbers where names go, and names where a number goes.
        #expect(read(["debug.glass.variant": 1, "debug.glass.host": true, "debug.glass.cards": 0.5]) == .default)
        #expect(read(["debug.glass.dim": ["0.2"], "debug.glass.sample": ["1"]]) == .default)
        // An empty string is not a name either.
        #expect(read(["debug.glass.variant": "", "debug.glass.dim": ""]) == .default)
    }

    @Test func aKeyThatIsNotOursChangesNothing() {
        #expect(read(["interface.look": "clear", "debug.glass": "clear", "debug.variant": "clear"]) == .default)
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
    }

    @Test func theTintFollowsTheAccentOnClearGlassToo() {
        let hint = accent.opacity(NotchTokens.glassTintOpacity)
        let plan = plan(tinted, NotchGlassSwitches(variant: .clear), bubbles: ["a"])
        #expect(plan.notch?.glass == Glass.clear.tint(hint))
        #expect(plan.notch?.glass != Glass.clear)
        #expect(plan.bubbles.first?.glass == Glass.clear.tint(hint).interactive())
    }

    @Test func theSwiftUIHostDrawsTheNotchWithGlassEffectAndTheAppKitHostDrawsItItself() {
        let swiftUI = plan(tinted, NotchGlassSwitches(host: .swiftui), bubbles: ["a"])
        #expect(swiftUI.notch?.id == .notch)
        #expect(swiftUI.appKitNotch == nil)

        let appKit = plan(tinted, NotchGlassSwitches(variant: .clear, host: .appkit), bubbles: ["a", "b"])
        #expect(appKit.notch == nil, "no glassEffect for the notch: an NSGlassEffectView draws it")
        #expect(appKit.appKitNotch == .init(variant: .clear, tint: accent.opacity(NotchTokens.glassTintOpacity)))
        #expect(appKit.bubbles.map(\.id) == [.bubble("a"), .bubble("b")], "the bubbles stay SwiftUI glass, of the same variant")
        #expect(appKit.bubbles.allSatisfy { $0.glass == Glass.clear.tint(accent.opacity(NotchTokens.glassTintOpacity)).interactive() })
        #expect(appKit.usesContainer)

        let untinted = plan(glass, NotchGlassSwitches(host: .appkit))
        #expect(untinted.appKitNotch == .init(variant: .regular, tint: nil))
    }

    @Test func theDimAndTheSchemeAreCarriedForTheViewsToDrawAndAreOnlyForTheContent() {
        let plan = plan(glass, NotchGlassSwitches(dim: 0.15, scheme: .dark))
        #expect(plan.dim == 0.15)
        #expect(plan.contentScheme == .dark)
        #expect(self.plan(glass, .default).dim == 0)
        #expect(self.plan(glass, .default).contentScheme == nil, "the system's scheme: nothing is forced")
        #expect(self.plan(glass, NotchGlassSwitches(scheme: .system)).contentScheme == nil)
    }

    // MARK: the inner container

    @Test func theCardsGetAnInnerContainerOnlyWhenTheyAreGlassOnGlass() {
        let spacing = NotchGlassPlan.innerContainerSpacing
        #expect(plan(glass, NotchGlassSwitches(cards: .glass)).cardContainerSpacing == spacing)
        #expect(plan(tinted, NotchGlassSwitches(variant: .clear, cards: .glass)).cardContainerSpacing == spacing)
        #expect(plan(glass, NotchGlassSwitches(cards: .fill)).cardContainerSpacing == nil)
        #expect(plan(glass, .default).cardContainerSpacing == nil)
        #expect(NotchGlassPlan.cardContainerSpacing(surface: glass, switches: NotchGlassSwitches(cards: .glass)) == spacing)
        for surface in [NotchSurface.solid, .material] {
            #expect(NotchGlassPlan.cardContainerSpacing(surface: surface, switches: NotchGlassSwitches(cards: .glass)) == nil)
        }
    }

    @Test func theInnerContainerBlendsNothingThatSitsASensibleGapApartAndIsNotTheNotchsOwn() {
        #expect(NotchGlassPlan.innerContainerSpacing > 0)
        #expect(NotchGlassPlan.innerContainerSpacing < 6, "cards, chips and fields sit 6 pt or more apart")
        #expect(NotchGlassPlan.innerContainerSpacing < NotchGlassPlan.containerSpacing, "tighter than the notch's own family")
    }

    // MARK: every switch is a no-op unless the notch is Liquid Glass

    @Test func theClassicNotchIsUntouchedWhateverTheSwitchesSay() {
        let everything = NotchGlassSwitches(variant: .clear, host: .appkit, dim: 0.4, scheme: .dark, sample: true, cards: .glass, selected: .white)
        for surface in [NotchSurface.solid, .material] {
            let plan = plan(surface, everything, bubbles: ["a", "b"])
            #expect(plan == .none, "\(surface)")
            #expect(plan.notch == nil && plan.appKitNotch == nil && plan.bubbles.isEmpty)
            #expect(plan.dim == 0)
            #expect(plan.contentScheme == nil)
            #expect(plan.cardContainerSpacing == nil)
            #expect(!plan.usesContainer)
        }
    }
}
