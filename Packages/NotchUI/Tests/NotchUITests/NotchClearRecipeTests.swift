import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// TEMPORARY (U3g step 1): the candidates for what "Trong vắt" is made of, and the two keys that choose among them. Step 2 deletes this
/// file with the candidates.
@Suite struct NotchClearRecipeTests {
    let accent = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.9)
    let glass = NotchSurface.liquidGlass(tinted: false)

    func plan(
        _ recipe: NotchClearRecipeSwitch, clarity: NotchGlassClarity = .clear, surface: NotchSurface? = nil, shape: NotchGlassShape = .slab,
        bubbles: [String] = [], open: Bool = false
    ) -> NotchGlassPlan {
        NotchGlassPlan(
            surface: surface ?? glass, bubbleIDs: bubbles, accent: accent,
            style: NotchGlassStyle(clarity: clarity, shape: shape, clearRecipe: recipe), isOpen: open
        )
    }

    // MARK: the keys

    func defaults(_ recipe: Any? = nil, tint: Any? = nil) -> UserDefaults {
        let defaults = makeIsolatedDefaults()
        if let recipe { defaults.set(recipe, forKey: "debug.glass.clearRecipe") }
        if let tint { defaults.set(tint, forKey: "debug.glass.clearTint") }
        return defaults
    }

    @Test func withNoKeysTheGlassIsToday() {
        #expect(NotchClearRecipeSwitch(reading: defaults()) == .default)
        #expect(NotchClearRecipeSwitch.default == NotchClearRecipeSwitch(recipe: .raw, tint: 0.12))
        #expect(NotchGlassStyle.default.clearRecipe == .default)
    }

    @Test func eachRecipeIsReadByItsNameIgnoringCaseAndSpaces() {
        for recipe in NotchClearRecipe.allCases {
            #expect(NotchClearRecipeSwitch(reading: defaults(recipe.rawValue)).recipe == recipe)
            #expect(NotchClearRecipeSwitch(reading: defaults("  \(recipe.rawValue.uppercased()) ")).recipe == recipe)
        }
        #expect(NotchClearRecipe.allCases.map(\.rawValue) == ["raw", "regularLight", "regularTint", "clearOverBlur", "regularOverBlur"])
    }

    @Test func aRecipeThatIsMissingOfAnotherTypeOrNotANameIsToday() {
        for value in [nil, "", "regular", "light", 1, true, 0.5] as [Any?] {
            #expect(NotchClearRecipeSwitch(reading: defaults(value)).recipe == .raw, "\(String(describing: value))")
        }
    }

    @Test func theTintIsANumberOrAStringHeldToItsRangeAndTodaysWhenItIsNothingElse() {
        func tint(_ value: Any?) -> Double { NotchClearRecipeSwitch(reading: defaults("regularTint", tint: value)).tint }
        #expect(tint(0.2) == 0.2 && tint("0.06") == 0.06 && tint(" 0.2 ") == 0.2 && tint(NSNumber(value: 0.12)) == 0.12)
        #expect(tint(0) == 0 && tint(5) == NotchClearRecipeSwitch.tintRange.upperBound && tint(-1) == 0)
        for value in [nil, "", "pale", true] as [Any?] where !(value is Bool) { #expect(tint(value) == 0.12, "\(String(describing: value))") }
        #expect(tint(Double.nan) == 0.12 && tint(Double.infinity) == 0.12)
        #expect(NotchClearRecipeSwitch.defaultTint == 0.12)
    }

    @Test func theMaterialIsReadByItsNameAndChosenForTheTwoBlurRecipesOnly() {
        func switches(_ value: Any?, recipe: String = "clearOverBlur") -> NotchClearRecipeSwitch {
            let defaults = defaults(recipe)
            if let value { defaults.set(value, forKey: "debug.glass.clearMaterial") }
            return NotchClearRecipeSwitch(reading: defaults)
        }
        for material in NotchBlurMaterial.allCases { #expect(switches(" \(material.rawValue.uppercased())").material == material) }
        #expect(NotchBlurMaterial.allCases.map(\.rawValue) == ["ultraThin", "thin", "regular", "thick", "ultraThick"])
        for value in [nil, "", "glass", 1] as [Any?] { #expect(switches(value).material == .ultraThin, "\(String(describing: value))") }
        #expect(plan(switches("thick")).materialUnder == .thick)
        #expect(plan(switches("thick", recipe: "regularOverBlur")).materialUnder == .thick)
        #expect(plan(switches("thick", recipe: "regularTint")).materialUnder == nil, "a recipe without a blur has no material")
        // Every case maps to its own material (`Material` is not Equatable; `String(describing:)` names the kind).
        #expect(Set(NotchBlurMaterial.allCases.map { String(describing: $0.material) }).count == 5)
    }

    // MARK: the glass

    @Test func eachRecipeIsItsGlassForClearAndNeverForBalanced() {
        let tint = 0.2
        let expected: [NotchClearRecipe: Glass] = [
            .raw: .clear, .regularLight: .regular, .regularTint: .regular.tint(.white.opacity(tint)), .clearOverBlur: .clear,
            .regularOverBlur: .regular,
        ]
        for recipe in NotchClearRecipe.allCases {
            let switches = NotchClearRecipeSwitch(recipe: recipe, tint: tint)
            #expect(NotchGlassClarity.clear.glass(under: switches) == expected[recipe], "\(recipe)")
            #expect(NotchGlassClarity.balanced.glass(under: switches) == Glass.regular, "\(recipe): balanced does not read it")
        }
        #expect(NotchGlassClarity.clear.glass == Glass.clear && NotchGlassClarity.balanced.glass == Glass.regular)
        // The tints differ, so three of them are three looks.
        let tints = [0.06, 0.12, 0.2].map { NotchClearRecipeSwitch(recipe: .regularTint, tint: $0).clearGlass }
        #expect(tints[0] != tints[1] && tints[1] != tints[2] && tints[0] != tints[2])
        #expect(tints.allSatisfy { $0 != Glass.regular })
    }

    @Test func aRecipeOnlyChangesTheClearPlanOfLiquidGlass() {
        for recipe in NotchClearRecipe.allCases {
            let switches = NotchClearRecipeSwitch(recipe: recipe)
            // Balanced: the plan is the one with no recipe at all.
            #expect(plan(switches, clarity: .balanced, bubbles: ["a"]) == plan(.default, clarity: .balanced, bubbles: ["a"]), "\(recipe)")
            #expect(plan(switches, clarity: .balanced, shape: .tiles, open: true) == plan(.default, clarity: .balanced, shape: .tiles, open: true))
            // The classic looks have no glass to change.
            for surface in [NotchSurface.solid, .material] {
                #expect(plan(switches, surface: surface) == .none, "\(recipe) on \(surface)")
            }
        }
        #expect(plan(.default) == plan(NotchClearRecipeSwitch(recipe: .raw), clarity: .clear), "raw is today's clear plan")
        #expect(plan(.default).notch?.glass == Glass.clear && plan(.default).forcedScheme == nil && plan(.default).materialUnder == nil)
    }

    @Test func theCandidatesGiveTheNotchTheTilesAndTheBubblesTheirGlass() {
        let tint = NotchClearRecipeSwitch(recipe: .regularTint, tint: 0.2)
        let hint = Glass.regular.tint(.white.opacity(0.2))
        let slab = plan(tint, bubbles: ["a"])
        #expect(slab.notch?.glass == hint && slab.bubbles.first?.glass == hint.interactive())
        let tiles = plan(tint, shape: .tiles, bubbles: ["a"])
        #expect(tiles.notch?.glass == hint && tiles.tiles?.tabBar.glass == hint && tiles.tiles?.content.glass == hint)
        #expect(plan(tint, shape: .tiles, open: true).notch?.glass == Glass.identity, "the open notch's own glass is still nothing")
        let light = plan(NotchClearRecipeSwitch(recipe: .regularLight), shape: .tiles)
        #expect(light.notch?.glass == Glass.regular && light.tiles?.content.glass == Glass.regular)
    }

    @Test func theAccentTintStillWinsWhenTheUserAsksForIt() {
        let hint = accent.opacity(NotchTokens.glassTintOpacity)
        let tinted = plan(NotchClearRecipeSwitch(recipe: .regularTint, tint: 0.2), surface: .liquidGlass(tinted: true))
        #expect(tinted.notch?.glass == Glass.regular.tint(hint))
    }

    @Test func theSchemeIsForcedOnlyByRegularLightAndTheBlurIsOnlyClearOverBlur() {
        for recipe in NotchClearRecipe.allCases {
            let switches = NotchClearRecipeSwitch(recipe: recipe)
            #expect(plan(switches).forcedScheme == (recipe == .regularLight ? .light : nil), "\(recipe)")
            let blurs = recipe == .clearOverBlur || recipe == .regularOverBlur
            #expect(plan(switches).materialUnder == (blurs ? .ultraThin : nil), "\(recipe)")
            #expect(plan(switches, shape: .tiles).materialUnder == (blurs ? .ultraThin : nil))
            let balanced = plan(switches, clarity: .balanced)
            #expect(balanced.forcedScheme == nil && balanced.materialUnder == nil, "\(recipe)")
        }
    }

    @Test func theThemeGivesTheRecipeItWasMadeWithToEveryStyleAndTodaysByDefault() {
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        let notifications = NotificationCenter()
        let made = NotchTheme(
            settings: settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: notifications, lookState: nil,
            clearRecipe: NotchClearRecipeSwitch(recipe: .regularTint, tint: 0.2)
        )
        #expect(made.glassStyle.clearRecipe == NotchClearRecipeSwitch(recipe: .regularTint, tint: 0.2))
        let plain = NotchTheme(settings: settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: notifications)
        #expect(plain.glassStyle == .default)
    }
}
