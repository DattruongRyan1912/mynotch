import Foundation
import NotchUI
import Testing
@testable import MediaModule

/// A cover colour as it is written in a design file.
private func hex(_ value: UInt32) -> SRGBColor { SRGBColor(hex: value) }

/// The smallest turn between two hues, in degrees, so 359 and 1 are 2 apart.
private func hueDistance(_ a: Double, _ b: Double) -> Double {
    let turn = abs(a - b).truncatingRemainder(dividingBy: 360)
    return min(turn, 360 - turn)
}

@Suite struct OKLCHTests {
    @Test func theColoursOfTheCornersAreWhereTheSpaceSaysTheyAre() {
        let black = OKLCH(.black)
        #expect(black.lightness < 1e-6 && black.chroma < 1e-6)
        let white = OKLCH(.white)
        #expect(abs(white.lightness - 1) < 1e-4 && white.chroma < 1e-4)
        let red = OKLCH(.fullRed)
        #expect(abs(red.lightness - 0.628) < 0.002 && abs(red.chroma - 0.258) < 0.002 && abs(red.hue - 29.2) < 0.3)
        let blue = OKLCH(.fullBlue)
        #expect(abs(blue.lightness - 0.452) < 0.002 && abs(blue.chroma - 0.313) < 0.002 && abs(blue.hue - 264.1) < 0.3)
    }

    @Test func aColourSurvivesTheWayThereAndBack() {
        for color in [hex(0x5A1010), hex(0x0B1E3F), hex(0xFFE066), hex(0x66CCFF), .fullGreen, .white, .black] {
            #expect(OKLCH(color).srgb.isClose(to: color, tolerance: 1e-4), "\(color)")
        }
    }

    @Test func aColourThatDoesNotFitLosesChromaAndKeepsItsLightnessAndHue() {
        let wanted = OKLCH(lightness: 0.9, chroma: 0.3, hue: 264)
        #expect(!wanted.fitsInSRGB)
        let fitted = OKLCH(wanted.srgb)
        #expect(abs(fitted.lightness - 0.9) < 0.005)
        #expect(hueDistance(fitted.hue, 264) < 1)
        #expect(fitted.chroma < 0.3)
    }

    @Test func theMostChromaThereIsAtALightnessIsWhatJustFits() {
        let most = OKLCH.maxChroma(lightness: 0.6, hue: 29)
        #expect(OKLCH(lightness: 0.6, chroma: most, hue: 29).fitsInSRGB)
        #expect(!OKLCH(lightness: 0.6, chroma: most + 0.01, hue: 29).fitsInSRGB)
        #expect(OKLCH.maxChroma(lightness: 0, hue: 29) < 1e-3)
        #expect(OKLCH.maxChroma(lightness: 1, hue: 29) < 1e-3)
    }
}

/// What the bars' colours must reach on each surface, and that they reach it with the hue they had.
@Suite struct SpectrumContrastTests {
    static let darkCovers: [(name: String, color: SRGBColor)] = [
        ("dark red", hex(0x5A1010)), ("navy", hex(0x0B1E3F)), ("dark green", hex(0x0F3D1E)), ("near black", hex(0x202020)),
        ("purple", hex(0x3A0F4D)),
    ]
    static let brightCovers: [(name: String, color: SRGBColor)] = [("yellow", hex(0xFFE066)), ("light blue", hex(0x66CCFF))]
    static let allCovers = darkCovers + brightCovers
    static let surfaces: [(name: String, surface: NotchSurface)] = [
        ("solid", .solid), ("material", .material), ("glass", .liquidGlass(tinted: false)), ("tinted glass", .liquidGlass(tinted: true)),
    ]
    static let glass = NotchSurface.liquidGlass(tinted: false)

    func contrast(_ color: SRGBColor, _ other: SRGBColor) -> Double { color.contrast(with: other) }

    /// The most the worse of the two glass contrasts can be: what the luminance that does equally well on both has on either.
    var bestOnGlass: Double {
        (SpectrumBackdrop.glass.minimumLuminance + 0.05) / (SpectrumBackdrop.darkGlass.luminance + 0.05)
    }

    // MARK: the targets

    @Test func nothingCanBeSeenAtThreeToOneOnBothGlassesAtOnce() {
        let (dark, light) = (SpectrumBackdrop.darkGlass.luminance, SpectrumBackdrop.lightGlass.luminance)
        let darkest = 3 * (dark + 0.05) - 0.05
        let lightest = (light + 0.05) / 3 - 0.05
        #expect(darkest > lightest, "a colour that beats the dark glass is too light to beat the light one: \(darkest) > \(lightest)")
    }

    @Test func theGlassRangeIsTheOneLuminanceThatDoesBestOnBothGlasses() {
        let range = SpectrumBackdrop.glass.luminanceRange
        #expect(range.lowerBound == range.upperBound, "no room: one luminance, which is the best of the two")
        let atBest = SRGBColor.black.lifted(toLuminance: range.lowerBound)
        let (onDark, onLight) = (contrast(atBest, SpectrumBackdrop.darkGlass), contrast(atBest, SpectrumBackdrop.lightGlass))
        #expect(abs(onDark - onLight) < 0.01, "equal on both, which is the most the worse of the two can be: \(onDark) \(onLight)")
        #expect(onDark > 2.5 && onDark < 3, "\(onDark)")
        #expect(abs(range.lowerBound - 0.205) < 0.005, "\(range.lowerBound)")
        for other in [range.lowerBound - 0.03, range.lowerBound + 0.03] {
            let moved = SRGBColor.black.lifted(toLuminance: other)
            #expect(min(contrast(moved, SpectrumBackdrop.darkGlass), contrast(moved, SpectrumBackdrop.lightGlass)) < min(onDark, onLight))
        }
    }

    @Test func blackAndTheVeilNeedFourAndAHalfToOneAndHaveNoCeiling() {
        #expect(abs(SpectrumBackdrop.black.minimumLuminance - 0.175) < 1e-9)
        let atFloor = SRGBColor.black.lifted(toLuminance: SpectrumBackdrop.veil.minimumLuminance)
        #expect(abs(contrast(atFloor, SpectrumBackdrop.veilGrey) - 4.5) < 1e-3)
        #expect(SpectrumBackdrop.black.maximumLuminance == 1 && SpectrumBackdrop.veil.maximumLuminance == 1)
    }

    @Test func everySurfaceMapsToItsBackdropAndATintDoesNotChangeIt() {
        #expect(SpectrumBackdrop(.solid) == .black)
        #expect(SpectrumBackdrop(.material) == .veil)
        #expect(SpectrumBackdrop(.liquidGlass(tinted: false)) == .glass)
        #expect(SpectrumBackdrop(.liquidGlass(tinted: true)) == .glass)
        #expect(SpectrumBackdrop.allCases.filter(\.hasEdge) == [.glass], "the edge is for glass alone")
    }

    // MARK: the colours

    @Test func everyCoverReachesTheTargetOnEverySurface() {
        for (name, cover) in Self.allCovers {
            let onBlack = cover.visible(on: .solid)
            #expect(onBlack.contrastOnBlack >= 4.5 - 1e-6, "\(name) on black: \(onBlack.contrastOnBlack)")
            let onVeil = cover.visible(on: .material)
            #expect(contrast(onVeil, SpectrumBackdrop.veilGrey) >= 4.5 - 1e-6, "\(name) on the veil")
            for surface in [NotchSurface.liquidGlass(tinted: false), .liquidGlass(tinted: true)] {
                let onGlass = cover.visible(on: surface)
                let (onDark, onLight) = (contrast(onGlass, SpectrumBackdrop.darkGlass), contrast(onGlass, SpectrumBackdrop.lightGlass))
                #expect(onDark >= bestOnGlass - 1e-4 && onLight >= bestOnGlass - 1e-4, "\(name) on glass: \(onDark) and \(onLight), the best being \(bestOnGlass)")
            }
        }
    }

    @Test func aBrightCoverThatAlreadyShowsOnBlackAndOnTheVeilIsLeftAlone() {
        for (name, cover) in Self.brightCovers {
            #expect(cover.visible(on: .solid) == cover, "\(name) on solid")
            #expect(cover.visible(on: .material) == cover, "\(name) on material")
        }
    }

    @Test func aBrightCoverIsDarkenedOnGlassToWhereBothGlassesSeeItEqually() {
        for (name, cover) in Self.brightCovers {
            for surface in [NotchSurface.liquidGlass(tinted: false), .liquidGlass(tinted: true)] {
                let shown = cover.visible(on: surface)
                #expect(abs(shown.luminance - SpectrumBackdrop.glass.minimumLuminance) < 1e-5, "\(name): \(shown.luminance)")
                #expect(OKLCH(shown).lightness < OKLCH(cover).lightness, "\(name) is darker, not lighter")
                #expect(hueDistance(OKLCH(shown).hue, OKLCH(cover).hue) <= 10, "\(name): \(OKLCH(cover).hue) became \(OKLCH(shown).hue)")
            }
        }
    }

    @Test func aColourIsMovedNoFurtherThanTheTargetNeeds() {
        for (name, cover) in Self.allCovers {
            for (surfaceName, surface) in Self.surfaces {
                let range = SpectrumBackdrop(surface).luminanceRange
                let shown = cover.visible(on: surface)
                if cover.luminance < range.lowerBound {
                    #expect(shown.luminance >= range.lowerBound - 1e-9 && shown.luminance < range.lowerBound + 1e-5, "\(name) on \(surfaceName): lifted to \(shown.luminance), the floor being \(range.lowerBound)")
                } else if cover.luminance > range.upperBound {
                    #expect(shown.luminance <= range.upperBound + 1e-9 && shown.luminance > range.upperBound - 1e-5, "\(name) on \(surfaceName): lowered to \(shown.luminance), the ceiling being \(range.upperBound)")
                } else {
                    #expect(shown == cover, "\(name) on \(surfaceName) is in range")
                }
            }
        }
    }

    @Test func theHueSurvivesTheMove() {
        for (name, cover) in Self.allCovers where OKLCH(cover).chroma > 0.03 {
            for (surfaceName, surface) in Self.surfaces {
                let shown = OKLCH(cover.visible(on: surface))
                #expect(hueDistance(shown.hue, OKLCH(cover).hue) <= 10, "\(name) on \(surfaceName): \(OKLCH(cover).hue) became \(shown.hue)")
            }
        }
    }

    @Test func aLiftedColourIsNotWashedOut() {
        for (name, cover) in Self.darkCovers where OKLCH(cover).chroma > 0.03 {
            let lifted = OKLCH(cover.visible(on: .solid))
            #expect(lifted.chroma >= OKLCH(cover).chroma, "\(name) gains lightness, not grey: \(OKLCH(cover).chroma) became \(lifted.chroma)")
        }
    }

    @Test func aGreyStaysGrey() {
        let grey = hex(0x202020)
        for (_, surface) in Self.surfaces {
            let lifted = grey.visible(on: surface)
            #expect(OKLCH(lifted).chroma < 0.005 && lifted.luminance > grey.luminance)
        }
        #expect(OKLCH(SRGBColor.white.visible(on: Self.glass)).chroma < 0.005, "a grey made darker too")
    }

    @Test func movingAgainChangesNothing() {
        for (_, cover) in Self.allCovers {
            for (_, surface) in Self.surfaces {
                let once = cover.visible(on: surface)
                #expect(once.visible(on: surface) == once)
            }
        }
    }

    @Test func blackBecomesTheDarkestGreyThatShows() {
        let lifted = SRGBColor.black.visible(on: .solid)
        #expect(abs(lifted.red - lifted.blue) < 1e-6)
        #expect(lifted.contrastOnBlack >= 4.5 - 1e-6 && lifted.contrastOnBlack < 4.5 + 1e-3)
    }

    // MARK: from a cover to a bar

    /// The whole way a cover takes: read from an image, tinted, spread along the bars, adjusted for the surface.
    func bars(ofCover cover: SRGBColor, on surface: NotchSurface) throws -> [SRGBColor] {
        let palette = try #require(ArtworkColorExtractor.palette(of: SyntheticImage.solid(cover)))
        let colors = try #require(SpectrumColorMode.artwork.colors(count: 4, tint: palette, start: SpectrumColorMode.defaultStart, end: SpectrumColorMode.defaultEnd))
        return colors.map { $0.visible(on: surface) }
    }

    @Test func aCoverKeepsItsHueFromTheImageToTheBars() throws {
        for (name, cover) in Self.allCovers where OKLCH(cover).chroma > 0.03 {
            for (surfaceName, surface) in Self.surfaces {
                for bar in try bars(ofCover: cover, on: surface) {
                    #expect(hueDistance(OKLCH(bar).hue, OKLCH(cover).hue) <= 10, "\(name) on \(surfaceName): \(OKLCH(cover).hue) became \(OKLCH(bar).hue)")
                }
            }
        }
    }

    @Test func aCoversBarsReachTheTargetOnEverySurface() throws {
        for (name, cover) in Self.allCovers {
            for (surfaceName, surface) in Self.surfaces {
                let range = SpectrumBackdrop(surface).luminanceRange
                for bar in try bars(ofCover: cover, on: surface) {
                    #expect(bar.luminance >= range.lowerBound - 1e-5 && bar.luminance <= range.upperBound + 1e-5, "\(name) on \(surfaceName): \(bar.luminance) outside \(range)")
                }
            }
        }
    }

    @Test func aBrightCoversBarsAreTheCoversColourOnBlackAndTheVeil() throws {
        for (name, cover) in Self.brightCovers {
            for surface in [NotchSurface.solid, .material] {
                for bar in try bars(ofCover: cover, on: surface) {
                    #expect(bar.isClose(to: cover, tolerance: 0.005), "\(name)")
                }
            }
        }
    }

    // MARK: the user's gradient

    @Test func aDarkGradientIsLiftedBarByBarAndOnlyAsFarAsNeeded() {
        let start = hex(0x1B1030)
        let end = hex(0x2A8CC0)
        let ramp = SpectrumColorMode.gradient.colors(count: 4, tint: nil, start: start, end: end) ?? []
        let floor = SpectrumBackdrop.black.minimumLuminance
        #expect(ramp.first?.luminance ?? 1 < floor, "the first bar needs a lift")
        #expect(ramp.last?.luminance ?? 0 > floor, "the last does not")
        for color in ramp {
            let shown = color.visible(on: .solid)
            if color.luminance >= floor {
                #expect(shown == color, "a bar that shows is the user's colour")
            } else {
                #expect(shown.luminance >= floor && shown.luminance < floor + 1e-5)
                #expect(hueDistance(OKLCH(shown).hue, OKLCH(color).hue) <= 10)
            }
        }
        let first = OKLCH(ramp[0]).lightness
        #expect(OKLCH(ramp[0].visible(on: .solid)).lightness > first, "lighter than it was")
    }

    @Test func aGradientThatShowsOnBlackAndTheVeilIsTheUsersColoursExactly() {
        let ramp = SpectrumColorMode.gradient.colors(count: 4, tint: nil, start: hex(0xFFB347), end: hex(0x66CCFF)) ?? []
        for surface in [NotchSurface.solid, .material] {
            #expect(ramp.map { $0.visible(on: surface) } == ramp)
        }
    }

    @Test func onGlassALightGradientIsMadeDarkerBarByBar() {
        let ramp = SpectrumColorMode.gradient.colors(count: 4, tint: nil, start: SpectrumColorMode.defaultStart, end: SpectrumColorMode.defaultEnd) ?? []
        let best = SpectrumBackdrop.glass.minimumLuminance
        #expect(ramp.last?.luminance ?? 0 > best, "the default cyan end is lighter than glass can take")
        for color in ramp {
            let shown = color.visible(on: Self.glass)
            #expect(abs(shown.luminance - best) < 1e-5, "\(color) became \(shown.luminance)")
            #expect(hueDistance(OKLCH(shown).hue, OKLCH(color).hue) <= 10)
        }
    }

    // MARK: white

    @Test func whiteIsTheOneModeThatIsNotAdjusted() {
        #expect(SpectrumColorMode.artwork.adjustsForSurface)
        #expect(SpectrumColorMode.gradient.adjustsForSurface)
        #expect(!SpectrumColorMode.white.adjustsForSurface)
        // That is what the exemption is for: white is lighter than glass can take, and the rule would make it grey.
        #expect(SRGBColor.white.visible(on: Self.glass) != .white)
        #expect(SRGBColor.white.visible(on: .solid) == .white && SRGBColor.white.visible(on: .material) == .white)
    }

    // MARK: the footnote

    @Test func theSettingsSayThatVeryDarkColoursAreBrightened() {
        let note = SpectrumColorRows.note(for: .gradient, tintIsOn: true)
        #expect(note == SpectrumColorRows.brightenedNote)
        #expect(SpectrumColorRows.brightenedNote.contains("sáng"))
        #expect(SpectrumColorRows.note(for: .white, tintIsOn: true) == nil)
    }
}
