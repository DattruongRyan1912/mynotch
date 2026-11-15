import Foundation
import Testing
@testable import MyNotchCore

@Suite struct DashboardGlassSpecTests {

    private let backdrops: [GlassRGBA] = [
        .black,
        .screenshotDark,
        .midGray,
        .white
    ]

    // MARK: - U1: glassSurfacesStayLuminousOverAnyDesktop
    @Test func glassSurfacesStayLuminousOverAnyDesktop() {
        for backdrop in backdrops {
            for surface in DashboardGlassSpec.Surface.allCases {
                let comp = DashboardGlassSpec.composite(surface.layers, over: backdrop)
                let luma = DashboardGlassSpec.luma255(comp)
                #expect(
                    luma >= 215.0,
                    "Surface \(surface) over backdrop \(backdrop) dropped below 215.0 luma (got \(luma))"
                )
            }

            // Layered luminosity hierarchy assertions
            let sidebarLuma = DashboardGlassSpec.luma255(DashboardGlassSpec.composite(DashboardGlassSpec.Surface.sidebar.layers, over: backdrop))
            #expect(sidebarLuma >= 225.0, "Sidebar over \(backdrop) must be >= 225.0 (got \(sidebarLuma))")

            let headerLuma = DashboardGlassSpec.luma255(DashboardGlassSpec.composite(DashboardGlassSpec.Surface.header.layers, over: backdrop))
            #expect(headerLuma >= 225.0, "Header over \(backdrop) must be >= 225.0 (got \(headerLuma))")

            let cardLuma = DashboardGlassSpec.luma255(DashboardGlassSpec.composite(DashboardGlassSpec.Surface.card.layers, over: backdrop))
            #expect(cardLuma >= 235.0, "Card over \(backdrop) must be >= 235.0 (got \(cardLuma))")
        }

        // Mathematical benchmark checkpoint over black backdrop
        let rootBlackComp = DashboardGlassSpec.composite(DashboardGlassSpec.Surface.root.layers, over: .black)
        let rootBlackLuma = DashboardGlassSpec.luma255(rootBlackComp)
        #expect(abs(rootBlackLuma - 219.3) <= 0.5, "Root wash over black benchmark must be 219.3 ± 0.5 (got \(rootBlackLuma))")
    }

    // MARK: - U2: textTokensMeetContrastOnEverySurface
    @Test func textTokensMeetContrastOnEverySurface() {
        for backdrop in backdrops {
            for surface in DashboardGlassSpec.Surface.allCases {
                let comp = DashboardGlassSpec.composite(surface.layers, over: backdrop)

                let primaryContrast = DashboardGlassSpec.wcagContrast(DashboardGlassSpec.textPrimary, comp)
                #expect(
                    primaryContrast >= 12.0,
                    "textPrimary failed 12:1 target on \(surface) over \(backdrop) (got \(primaryContrast))"
                )

                let secondaryContrast = DashboardGlassSpec.wcagContrast(DashboardGlassSpec.textSecondary, comp)
                #expect(
                    secondaryContrast >= 7.0,
                    "textSecondary failed 7:1 AAA target on \(surface) over \(backdrop) (got \(secondaryContrast))"
                )
            }
        }
    }

    // MARK: - U3: semanticTextMeetsAA
    @Test func semanticTextMeetsAA() {
        let semanticTokens: [(name: String, token: GlassRGBA)] = [
            ("textMuted", DashboardGlassSpec.textMuted),
            ("accentText", DashboardGlassSpec.accentText),
            ("successText", DashboardGlassSpec.successText),
            ("warningText", DashboardGlassSpec.warningText),
            ("dangerText", DashboardGlassSpec.dangerText)
        ]

        for backdrop in backdrops {
            for surface in DashboardGlassSpec.Surface.allCases {
                let comp = DashboardGlassSpec.composite(surface.layers, over: backdrop)
                for (name, token) in semanticTokens {
                    let contrast = DashboardGlassSpec.wcagContrast(token, comp)
                    #expect(
                        contrast >= 4.5,
                        "\(name) failed 4.5:1 AA target on \(surface) over \(backdrop) (got \(contrast))"
                    )
                }
            }
        }

        // Test semantic text on tinted badge surfaces over black backdrop
        let badgeTints: [(name: String, tint: GlassRGBA, text: GlassRGBA)] = [
            ("successBadge", GlassRGBA(r: 16, g: 185, b: 129, a: 0.12), DashboardGlassSpec.successText),
            ("warningBadge", GlassRGBA(r: 245, g: 158, b: 11, a: 0.12), DashboardGlassSpec.warningText),
            ("dangerBadge", GlassRGBA(r: 239, g: 68, b: 68, a: 0.12), DashboardGlassSpec.dangerText)
        ]
        for item in badgeTints {
            let badgeComp = DashboardGlassSpec.composite([DashboardGlassSpec.rootWash, DashboardGlassSpec.headerFill, item.tint], over: .black)
            let contrast = DashboardGlassSpec.wcagContrast(item.text, badgeComp)
            #expect(contrast >= 4.5, "\(item.name) text failed 4.5:1 AA contrast over tinted badge (got \(contrast))")
        }
    }

    // MARK: - U4: surfacesAreDistinguishable
    @Test func surfacesAreDistinguishable() {
        let testBackdrops: [GlassRGBA] = [.black, .screenshotDark]
        for backdrop in testBackdrops {
            let rootComp = DashboardGlassSpec.composite(DashboardGlassSpec.Surface.root.layers, over: backdrop)
            let cardComp = DashboardGlassSpec.composite(DashboardGlassSpec.Surface.card.layers, over: backdrop)
            let insetComp = DashboardGlassSpec.composite(DashboardGlassSpec.Surface.inset.layers, over: backdrop)
            let borderComp = DashboardGlassSpec.composite([DashboardGlassSpec.rootWash, DashboardGlassSpec.card, DashboardGlassSpec.insetBorder], over: backdrop)

            let rootLuma = DashboardGlassSpec.luma255(rootComp)
            let cardLuma = DashboardGlassSpec.luma255(cardComp)
            let insetLuma = DashboardGlassSpec.luma255(insetComp)
            let borderLuma = DashboardGlassSpec.luma255(borderComp)

            // Card must be noticeably brighter than root wash (>= 12.0 threshold restored)
            let cardDiff = cardLuma - rootLuma
            #expect(cardDiff >= 12.0, "Card over \(backdrop) should be at least 12 luma units brighter than root (got \(cardDiff))")

            // Inset must be visibly distinguished from card (>= 8.0 threshold restored)
            let insetDiff = cardLuma - insetLuma
            #expect(insetDiff >= 8.0, "Inset over \(backdrop) should be at least 8 luma units darker than card (got \(insetDiff))")

            // Inset border must be clearly darker than inset interior (>= 20.0 threshold restored)
            let borderDiff = insetLuma - borderLuma
            #expect(borderDiff >= 20.0, "Inset border over \(backdrop) should be at least 20 luma units darker than inset (got \(borderDiff))")
        }

        // Separator alpha must guarantee visible hairline
        #expect(DashboardGlassSpec.separator.a >= 0.08, "Separator alpha should be at least 0.08")
    }

    // MARK: - U5: compositeMathEdges
    @Test func compositeMathEdges() {
        let base = GlassRGBA(r: 100, g: 100, b: 100, a: 1.0)

        // Alpha = 0 should leave color unchanged
        let zeroAlpha = GlassRGBA(r: 255, g: 0, b: 0, a: 0.0)
        let c1 = DashboardGlassSpec.composite([zeroAlpha], over: base)
        #expect(abs(c1.r - 100) < 0.001)

        // Alpha = 1.0 should replace color completely
        let opaque = GlassRGBA(r: 200, g: 50, b: 20, a: 1.0)
        let c2 = DashboardGlassSpec.composite([opaque], over: base)
        #expect(abs(c2.r - 200) < 0.001)
        #expect(abs(c2.g - 50) < 0.001)
        #expect(abs(c2.b - 20) < 0.001)

        // Half opacity
        let half = GlassRGBA(r: 200, g: 100, b: 0, a: 0.5)
        let c3 = DashboardGlassSpec.composite([half], over: base)
        // 200 * 0.5 + 100 * 0.5 = 150
        #expect(abs(c3.r - 150) < 0.001)
        #expect(abs(c3.g - 100) < 0.001)
        #expect(abs(c3.b - 50) < 0.001)

        // Empty layers array should return backdrop unchanged
        let cEmpty = DashboardGlassSpec.composite([], over: base)
        #expect(abs(cEmpty.r - base.r) < 0.001)
        #expect(abs(cEmpty.g - base.g) < 0.001)
        #expect(abs(cEmpty.b - base.b) < 0.001)

        // Alpha clamping: alpha < 0 treated as 0, alpha > 1 treated as 1
        let negativeAlpha = GlassRGBA(r: 255, g: 0, b: 0, a: -0.5)
        let cNeg = DashboardGlassSpec.composite([negativeAlpha], over: base)
        #expect(abs(cNeg.r - base.r) < 0.001)

        let overAlpha = GlassRGBA(r: 255, g: 0, b: 0, a: 1.5)
        let cOver = DashboardGlassSpec.composite([overAlpha], over: base)
        #expect(abs(cOver.r - 255) < 0.001)
    }

    // MARK: - U6: wcagMathSanity
    @Test func wcagMathSanity() {
        let white = GlassRGBA.white
        let black = GlassRGBA.black

        let maxContrast = DashboardGlassSpec.wcagContrast(white, black)
        #expect(abs(maxContrast - 21.0) < 0.05)

        let sameContrast = DashboardGlassSpec.wcagContrast(white, white)
        #expect(abs(sameContrast - 1.0) < 0.001)

        // Commutativity
        let c1 = DashboardGlassSpec.wcagContrast(DashboardGlassSpec.textPrimary, white)
        let c2 = DashboardGlassSpec.wcagContrast(white, DashboardGlassSpec.textPrimary)
        #expect(abs(c1 - c2) < 0.001)

        // Slate 500 contrast against white sanity (between 4.7 and 4.8)
        let slateContrast = DashboardGlassSpec.wcagContrast(GlassRGBA.slate500, white)
        #expect(slateContrast >= 4.7 && slateContrast <= 4.8, "Slate500 on white contrast must be between 4.7 and 4.8 (got \(slateContrast))")
    }

    // MARK: - U7: legacyGlassWouldFail
    @Test func legacyGlassWouldFail() {
        // Without rootWash, legacy card was white.opacity(0.42) directly over dark desktop
        let legacyCardLayer = GlassRGBA(r: 255, g: 255, b: 255, a: 0.42)
        let legacyComp = DashboardGlassSpec.composite([legacyCardLayer], over: .screenshotDark)
        let legacyLuma = DashboardGlassSpec.luma255(legacyComp)

        // Prove that legacy luma failed the luminous requirement (< 215.0)
        #expect(legacyLuma < 215.0, "Legacy glass without root wash was muddy: luma \(legacyLuma)")
        #expect(legacyLuma < 135.0, "Legacy glass on dark wallpaper drops to ~125 luma")

        // Prove that legacy contrast for secondary/muted text was degraded below AA 4.5:1 target
        let legacySecondaryContrast = DashboardGlassSpec.wcagContrast(DashboardGlassSpec.textSecondary, legacyComp)
        #expect(legacySecondaryContrast < 4.5, "Legacy secondary text contrast failed 4.5:1 AA (got \(legacySecondaryContrast))")
    }
}
