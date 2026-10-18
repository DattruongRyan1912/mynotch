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

/// What the bars' colours must reach on each surface, and that they reach it with the hue they had, by being lifted and never darkened.
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

    // MARK: the targets

    @Test func theTargetsAreFourAndAHalfOnBlackAndTheVeilAndThreeOnDarkGlass() {
        #expect(abs(SpectrumBackdrop.black.minimumLuminance - 0.175) < 1e-9)
        for backdrop in SpectrumBackdrop.allCases {
            let atFloor = SRGBColor.black.lifted(toLuminance: backdrop.minimumLuminance)
            #expect(abs(contrast(atFloor, backdrop.reference) - backdrop.target) < 1e-3, "\(backdrop)")
        }
        #expect(SpectrumBackdrop.black.target == 4.5 && SpectrumBackdrop.veil.target == 4.5 && SpectrumBackdrop.glass.target == 3)
        #expect(SpectrumBackdrop.glass.reference == SRGBColor(hex: 0x3A3F46))
        #expect(abs(SpectrumBackdrop.glass.minimumLuminance - 0.247) < 0.002, "\(SpectrumBackdrop.glass.minimumLuminance)")
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
            for (surfaceName, surface) in Self.surfaces {
                let backdrop = SpectrumBackdrop(surface)
                let shown = cover.visible(on: surface)
                #expect(contrast(shown, backdrop.reference) >= backdrop.target - 1e-6, "\(name) on \(surfaceName): \(contrast(shown, backdrop.reference))")
            }
        }
    }

    @Test func aColourThatAlreadyShowsIsExactlyAsItWas() {
        for (name, cover) in Self.brightCovers {
            for (surfaceName, surface) in Self.surfaces {
                #expect(cover.visible(on: surface) == cover, "\(name) on \(surfaceName)")
            }
        }
        #expect(SRGBColor.white.visible(on: Self.glass) == .white)
    }

    @Test func aColourIsNeverMadeDarker() {
        for (name, cover) in Self.allCovers + [("white", .white), ("black", .black)] {
            for (surfaceName, surface) in Self.surfaces {
                #expect(cover.visible(on: surface).luminance >= cover.luminance, "\(name) on \(surfaceName)")
            }
        }
    }

    @Test func aColourIsLiftedNoFurtherThanTheTargetNeeds() {
        for (name, cover) in Self.allCovers {
            for (surfaceName, surface) in Self.surfaces {
                let floor = SpectrumBackdrop(surface).minimumLuminance
                guard cover.luminance < floor else { continue }
                let lifted = cover.visible(on: surface)
                #expect(lifted.luminance >= floor, "\(name) on \(surfaceName)")
                #expect(lifted.luminance < floor + 1e-5, "\(name) on \(surfaceName): \(lifted.luminance) for a floor of \(floor)")
            }
        }
    }

    @Test func theHueSurvivesTheLift() {
        for (name, cover) in Self.allCovers where OKLCH(cover).chroma > 0.03 {
            for (surfaceName, surface) in Self.surfaces {
                let lifted = OKLCH(cover.visible(on: surface))
                #expect(hueDistance(lifted.hue, OKLCH(cover).hue) <= 10, "\(name) on \(surfaceName): \(OKLCH(cover).hue) became \(lifted.hue)")
            }
        }
    }

    @Test func aLiftedColourIsNotWashedOut() {
        for (name, cover) in Self.darkCovers where OKLCH(cover).chroma > 0.03 {
            for (surfaceName, surface) in Self.surfaces {
                let lifted = OKLCH(cover.visible(on: surface))
                #expect(lifted.chroma >= OKLCH(cover).chroma, "\(name) on \(surfaceName) gains lightness, not grey: \(OKLCH(cover).chroma) became \(lifted.chroma)")
            }
        }
    }

    @Test func aGreyStaysGrey() {
        let grey = hex(0x202020)
        for (_, surface) in Self.surfaces {
            let lifted = grey.visible(on: surface)
            #expect(OKLCH(lifted).chroma < 0.005 && lifted.luminance > grey.luminance)
        }
    }

    @Test func liftingAgainChangesNothing() {
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

    /// The whole way a cover takes: read from an image, tinted, spread along the bars, lifted for the surface.
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
                let backdrop = SpectrumBackdrop(surface)
                for bar in try bars(ofCover: cover, on: surface) {
                    #expect(contrast(bar, backdrop.reference) >= backdrop.target - 1e-4, "\(name) on \(surfaceName): \(contrast(bar, backdrop.reference))")
                }
            }
        }
    }

    @Test func aBrightCoversBarsAreTheCoversColourOnEverySurface() throws {
        for (name, cover) in Self.brightCovers {
            for (surfaceName, surface) in Self.surfaces {
                for bar in try bars(ofCover: cover, on: surface) {
                    #expect(bar.isClose(to: cover, tolerance: 0.005), "\(name) on \(surfaceName)")
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

    @Test func aGradientThatAlreadyShowsIsTheUsersColoursExactlyOnEverySurface() {
        let ramp = SpectrumColorMode.gradient.colors(count: 4, tint: nil, start: hex(0xFFB347), end: hex(0x66CCFF)) ?? []
        for (_, surface) in Self.surfaces {
            #expect(ramp.map { $0.visible(on: surface) } == ramp)
        }
    }

    @Test func theDefaultGradientKeepsItsCyanOnGlassAndOnlyItsDarkPurpleEndIsLifted() {
        let ramp = SpectrumColorMode.gradient.colors(count: 4, tint: nil, start: SpectrumColorMode.defaultStart, end: SpectrumColorMode.defaultEnd) ?? []
        let shown = ramp.map { $0.visible(on: Self.glass) }
        #expect(shown.last == SpectrumColorMode.defaultEnd, "the cyan end is as the user has it")
        #expect(shown.first != ramp.first, "the purple end is a little too dark for dark glass")
        #expect(shown.first?.luminance ?? 0 >= SpectrumBackdrop.glass.minimumLuminance)
        #expect(zip(shown, ramp).allSatisfy { $0.luminance >= $1.luminance })
    }

    // MARK: white

    @Test func whiteStaysWhiteOnEverySurface() {
        let white = SpectrumColorMode.white.colors(count: 4, tint: nil, start: SpectrumColorMode.defaultStart, end: SpectrumColorMode.defaultEnd) ?? []
        for (name, surface) in Self.surfaces {
            #expect(white.map { $0.visible(on: surface) } == white, "\(name)")
        }
    }

    // MARK: the footnote

    @Test func theSettingsSayThatVeryDarkColoursAreBrightened() {
        let note = SpectrumColorRows.note(for: .gradient, tintIsOn: true)
        #expect(note == SpectrumColorRows.brightenedNote)
        #expect(SpectrumColorRows.brightenedNote.contains("sáng"))
        #expect(SpectrumColorRows.note(for: .white, tintIsOn: true) == nil)
    }
}
