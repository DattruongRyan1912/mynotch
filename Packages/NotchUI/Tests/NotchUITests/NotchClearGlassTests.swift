import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// "Trong vắt" is `Glass.clear` with a material under every shape of the notch's family (the notch, the tiles, the bubbles); "Cân bằng" and
/// the classic looks have none. Nothing here draws: the plan is what the views draw from, and the layers are checked by the canary.
@Suite struct NotchClearGlassTests {
    let accent = Color(.sRGB, red: 0.2, green: 0.4, blue: 0.9)

    func plan(
        _ clarity: NotchGlassClarity, surface: NotchSurface = .liquidGlass(tinted: false), shape: NotchGlassShape = .slab,
        bubbles: [String] = [], open: Bool = false
    ) -> NotchGlassPlan {
        NotchGlassPlan(
            surface: surface, bubbleIDs: bubbles, accent: accent, style: NotchGlassStyle(clarity: clarity, shape: shape), isOpen: open
        )
    }

    @Test func onlyTheClearClarityBlursBehindItsGlass() {
        #expect(NotchGlassClarity.clear.blursBehind && !NotchGlassClarity.balanced.blursBehind)
        #expect(NotchGlassClarity.clear.glass == Glass.clear && NotchGlassClarity.balanced.glass == Glass.regular)
        for shape in NotchGlassShape.allCases {
            for open in [false, true] {
                #expect(plan(.clear, shape: shape, bubbles: ["a"], open: open).blursUnder, "\(shape), open \(open)")
                #expect(!plan(.balanced, shape: shape, bubbles: ["a"], open: open).blursUnder, "\(shape), open \(open)")
            }
        }
        #expect(NotchGlassPlan.none.blursUnder == false)
    }

    @Test func theClassicLooksHaveNothingToBlurUnderWhateverTheClarityIs() {
        for surface in [NotchSurface.solid, .material] {
            for clarity in NotchGlassClarity.allCases {
                #expect(plan(clarity, surface: surface) == .none, "\(surface), \(clarity)")
            }
        }
    }

    @Test func theGlassIsTheClearOneForTheNotchTheTilesAndTheBubblesAndTheAccentTintStillShows() {
        for shape in NotchGlassShape.allCases {
            let clear = plan(.clear, shape: shape, bubbles: ["a", "b"])
            #expect(clear.notch?.glass == Glass.clear)
            #expect(clear.bubbles.allSatisfy { $0.glass == Glass.clear.interactive() })
            if shape == .tiles { #expect(clear.tiles?.tabBar.glass == Glass.clear && clear.tiles?.content.glass == Glass.clear) }
        }
        let hint = accent.opacity(NotchTokens.glassTintOpacity)
        #expect(plan(.clear, surface: .liquidGlass(tinted: true)).notch?.glass == Glass.clear.tint(hint))
    }

    @Test func theMaterialIsTheThinnestAndTheSettingsAreStillOnlyTheTwo() {
        // Every SwiftUI material blurs alike (measured, in the canary); the thinnest adds the least grey.
        #expect(String(describing: NotchGlassPlan.blurMaterial) == String(describing: Material.ultraThinMaterial))
        #expect(NotchGlassStyle.default == NotchGlassStyle(clarity: .balanced, shape: .slab))
        let settings = SettingsStore(defaults: makeIsolatedDefaults())
        let theme = NotchTheme(settings: settings, systemAccent: { NotchAccent.Palette.blue.rgb }, notifications: NotificationCenter())
        settings.set(.clear, for: InterfaceSettings.glassClarity)
        #expect(theme.glassStyle == NotchGlassStyle(clarity: .clear, shape: .slab))
    }
}
