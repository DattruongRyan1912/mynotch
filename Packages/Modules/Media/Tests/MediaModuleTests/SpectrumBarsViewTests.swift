import AppKit
import MyNotchTestSupport
import NotchUI
import Observation
import SwiftUI
import Testing
@testable import MediaModule

/// The bars' layers and what makes the view count as bars on screen, with a manual clock for the redraws.
@Suite struct SpectrumBarsViewTests {
    static let epoch = Date(timeIntervalSinceReferenceDate: 1_000)
    let scheduler: ManualScheduler
    let store: NowPlayingStore
    /// The accent the bars are made with: what their notch's environment says.
    let notchAccent = CGColor(srgbRed: 0.2, green: 0.7, blue: 0.4, alpha: 1)

    /// The store's clock is the manual scheduler's, from `epoch`: the bars' driver and the made-up motion's phase read it.
    init() {
        let scheduler = ManualScheduler()
        self.scheduler = scheduler
        store = NowPlayingStore(lookUpApp: { _ in nil }, scheduler: scheduler, now: Self.clock(of: scheduler))
        store.apply(line: AdapterLines.track(), receivedAt: Date())
    }

    static func clock(of scheduler: ManualScheduler) -> () -> Date {
        { epoch + Double(scheduler.now.components.seconds) + Double(scheduler.now.components.attoseconds) / 1e18 }
    }

    func makeView() -> SpectrumBarsView {
        SpectrumBarsView(store: store, accent: notchAccent)
    }

    /// The view in a window, the way SwiftUI puts it in the notch's.
    func attach(_ view: SpectrumBarsView) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 40, height: 30), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = view
        view.frame = CGRect(origin: .zero, size: NowPlayingBars.size)
        view.layoutSubtreeIfNeeded()
        return window
    }

    func heights(_ view: SpectrumBarsView) -> [CGFloat] {
        view.layer?.sublayers?.map(\.frame.height) ?? []
    }

    @Test func sizeIsFourBarsAndTheirGaps() {
        #expect(NowPlayingBars.size == CGSize(width: 18, height: 14))
    }

    @Test func barsAreCapsulesInTheAccentColourSideBySideAndCentred() throws {
        let view = makeView()
        let window = attach(view)
        store.showSpectrum([0, 0.5, 1, 0.25])
        scheduler.advance(by: .milliseconds(40))
        let layers = try #require(view.layer?.sublayers)
        #expect(layers.count == 4)
        let expected: [CGFloat] = [3, 3 + 11 * 0.5, 14, 3 + 11 * 0.25]
        for (index, layer) in layers.enumerated() {
            #expect(layer.frame.width == 3)
            #expect(abs(layer.frame.height - expected[index]) < 0.0001)
            #expect(layer.frame.minX == CGFloat(index) * 5)
            #expect(abs(layer.frame.midY - 7) < 0.0001)
            #expect(layer.cornerRadius == 1.5)
        }
        #expect(layers[0].backgroundColor == notchAccent)
        window.contentView = nil
    }

    @Test func barsAreCentredInAViewLargerThanTheirs() throws {
        let view = makeView()
        let window = attach(view)
        view.frame = CGRect(x: 0, y: 0, width: 40, height: 30)
        view.layoutSubtreeIfNeeded()
        let layers = try #require(view.layer?.sublayers)
        #expect(layers[0].frame.minX == 11)
        #expect(abs(layers[0].frame.midY - 15) < 0.0001)
        window.contentView = nil
    }

    @Test func aPerFrameRedrawIsNeverAnimated() {
        let view = makeView()
        let window = attach(view)
        store.showSpectrum([0.2, 0.2, 0.2, 0.2])
        scheduler.advance(by: .milliseconds(40))
        store.showSpectrum([0.8, 0.8, 0.8, 0.8])
        scheduler.advance(by: .milliseconds(40))
        #expect(heights(view).allSatisfy { abs($0 - 11.8) < 0.001 })
        #expect(view.layer?.sublayers?.allSatisfy { $0.animationKeys() == nil } == true)
        window.contentView = nil
    }

    @Test func pausingEasesTheBarsToRestAndPlayingMovesThemAgainAtOnce() async throws {
        let view = makeView()
        let window = attach(view)
        store.showSpectrum([0.8, 0.8, 0.8, 0.8])
        scheduler.advance(by: .milliseconds(40))
        #expect(heights(view).allSatisfy { abs($0 - 11.8) < 0.001 })
        let first = try #require(view.layer?.sublayers?.first)

        store.apply(line: AdapterLines.playing(false), receivedAt: Date())
        for _ in 0..<100 where abs(first.frame.height - 3) > 0.001 { await Task.yield() }
        #expect(heights(view).allSatisfy { abs($0 - 3) < 0.001 })

        store.apply(line: AdapterLines.playing(true), receivedAt: Date())
        for _ in 0..<100 where abs(first.frame.height - 3) < 0.001 { await Task.yield() }
        #expect(heights(view).allSatisfy { abs($0 - 11.8) < 0.001 })
        window.contentView = nil
    }

    // MARK: - Colours

    let tint = ArtworkPalette(primary: SRGBColor(red: 0.9, green: 0.2, blue: 0.1), secondary: SRGBColor(red: 0.1, green: 0.4, blue: 0.9))

    func srgb(_ color: SRGBColor) -> CGColor { CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1) }

    func colours(_ view: SpectrumBarsView) -> [CGColor?] { view.layer?.sublayers?.map(\.backgroundColor) ?? [] }

    /// What the bars show for `mode` on `surface`: the colours of the choice, adjusted to show there unless the choice is white.
    func expectedColours(
        _ mode: SpectrumColorMode, tint: ArtworkPalette? = nil, start: SRGBColor = SpectrumColorMode.defaultStart,
        end: SRGBColor = SpectrumColorMode.defaultEnd, surface: NotchSurface = .solid
    ) -> [CGColor?] {
        (mode.colors(count: 4, tint: tint, start: start, end: end) ?? []).map { srgb(mode.adjustsForSurface ? $0.visible(on: surface) : $0) }
    }

    var accent: [CGColor?] { Array(repeating: notchAccent, count: 4) }

    @Test func theBarsKeepTheAccentColourUntilAnythingElseIsAsked() {
        let view = makeView()
        #expect(colours(view) == accent)
        store.showTint(tint)
        store.setTintEnabled(false)
        let other = makeView()
        #expect(colours(other) == accent, "a tint that is switched off colours nothing")
    }

    @Test func aViewMadeLaterStartsWithTheColoursTheStoreHasNow() {
        store.showTint(tint)
        let view = makeView()
        #expect(colours(view) == expectedColours(.artwork, tint: tint))
    }

    @Test func theCoversColoursReachABarsViewThatIsAlreadyOnScreenAtOnce() {
        let view = makeView()
        let window = attach(view)
        store.showTint(tint)
        #expect(colours(view) == expectedColours(.artwork, tint: tint))
        #expect(colours(view).first != colours(view).last, "two colours make a gradient along the bars")
        window.contentView = nil
    }

    @Test func theTintGoingAwayBringsTheAccentBack() {
        let view = makeView()
        let window = attach(view)
        store.showTint(tint)
        #expect(colours(view) != accent)
        store.showTint(nil)
        #expect(colours(view) == accent)
        window.contentView = nil
    }

    @Test func whiteAndGradientAreAppliedToTheLayers() {
        let view = makeView()
        let window = attach(view)
        store.setSpectrumColors(mode: .white, start: SpectrumColorMode.defaultStart, end: SpectrumColorMode.defaultEnd)
        #expect(colours(view) == expectedColours(.white))
        let start = SRGBColor(red: 1, green: 0.5, blue: 0)
        let end = SRGBColor(red: 0, green: 0.5, blue: 1)
        store.setSpectrumColors(mode: .gradient, start: start, end: end)
        #expect(colours(view) == expectedColours(.gradient, start: start, end: end))
        window.contentView = nil
    }

    @Test func aColourChangeMovesNoBarAndAnimatesNothing() {
        let view = makeView()
        let window = attach(view)
        store.showSpectrum([0.2, 0.4, 0.6, 0.8])
        scheduler.advance(by: .milliseconds(40))
        let before = heights(view)
        store.showTint(tint)
        #expect(colours(view) != accent)
        #expect(heights(view) == before)
        #expect(view.layer?.sublayers?.allSatisfy { $0.animationKeys() == nil } == true)
        window.contentView = nil
    }

    @Test func barsOffScreenTakeTheNewColoursTheMomentTheyAreBack() {
        let view = makeView()
        let window = attach(view)
        view.isNotchOnScreen = false
        store.showTint(tint)
        view.isNotchOnScreen = true
        #expect(colours(view) == expectedColours(.artwork, tint: tint))
        window.contentView = nil
    }

    // MARK: - Surfaces

    let glass = NotchSurface.liquidGlass(tinted: false)
    /// Covers whose colours show on none of the surfaces as they are.
    let darkTint = ArtworkPalette(primary: SRGBColor(hex: 0x5A1010), secondary: SRGBColor(hex: 0x0B1E3F))

    func makeView(on surface: NotchSurface) -> SpectrumBarsView {
        SpectrumBarsView(store: store, accent: notchAccent, surface: surface)
    }

    func components(_ color: CGColor?) -> [CGFloat] { color?.components ?? [] }

    func srgbColors(_ view: SpectrumBarsView) -> [SRGBColor] {
        colours(view).map { color in
            let c = components(color)
            return SRGBColor(red: Double(c[0]), green: Double(c[1]), blue: Double(c[2]))
        }
    }

    func edge(_ view: SpectrumBarsView) -> [Float] { view.layer?.sublayers?.map(\.shadowOpacity) ?? [] }

    @Test func theBarsAreLiftedForTheSurfaceTheyAreOn() {
        store.showTint(darkTint)
        for (surface, floor) in [(NotchSurface.solid, 0.175), (.material, SpectrumBackdrop.veil.minimumLuminance), (glass, SpectrumBackdrop.glass.minimumLuminance)] {
            let shown = srgbColors(makeView(on: surface))
            #expect(shown.count == 4)
            #expect(shown.allSatisfy { $0.luminance >= floor - 1e-6 }, "\(surface): \(shown.map(\.luminance)) under \(floor)")
            #expect(colours(makeView(on: surface)) == expectedColours(.artwork, tint: darkTint, surface: surface))
        }
        #expect(colours(makeView(on: .solid)) != colours(makeView(on: .material)), "the veil asks for more than black does")
    }

    @Test func glassGivesEveryBarAThinDarkEdgeAndTheOtherSurfacesNone() throws {
        for tinted in [false, true] {
            let view = makeView(on: .liquidGlass(tinted: tinted))
            #expect(edge(view) == [0.35, 0.35, 0.35, 0.35])
            let bar = try #require(view.layer?.sublayers?.first)
            #expect(bar.shadowRadius == 1 && bar.shadowOffset == .zero)
            #expect(components(bar.shadowColor) == [0, 1], "black")
        }
        #expect(edge(makeView(on: .solid)) == [0, 0, 0, 0])
        #expect(edge(makeView(on: .material)) == [0, 0, 0, 0])
    }

    @Test func theEdgeIsOnTheAccentBarsAndOnWhiteOnesToo() {
        #expect(colours(makeView(on: glass)) == accent, "no cover yet: the accent, as the user picked it")
        #expect(edge(makeView(on: glass)) == [0.35, 0.35, 0.35, 0.35])
        store.setSpectrumColors(mode: .white, start: SpectrumColorMode.defaultStart, end: SpectrumColorMode.defaultEnd)
        let white = makeView(on: glass)
        #expect(colours(white) == expectedColours(.white))
        #expect(srgbColors(white).allSatisfy { $0 == .white }, "white stays white, edge or not")
        #expect(edge(white) == [0.35, 0.35, 0.35, 0.35])
    }

    @Test func theAccentIsNotLiftedWhateverTheSurfaceIs() {
        let dark = CGColor(srgbRed: 0.02, green: 0.02, blue: 0.1, alpha: 1)
        for surface in [NotchSurface.solid, .material, glass] {
            #expect(colours(SpectrumBarsView(store: store, accent: dark, surface: surface)) == Array(repeating: dark, count: 4))
        }
    }

    @Test func aGradientIsLiftedWhereTheUsersColoursAreTooDark() {
        let start = SRGBColor(hex: 0x1B1030)
        let end = SRGBColor(hex: 0x2A8CC0)
        store.setSpectrumColors(mode: .gradient, start: start, end: end)
        let view = makeView(on: .solid)
        #expect(colours(view) == expectedColours(.gradient, start: start, end: end))
        #expect(colours(view) != (SpectrumColorMode.gradient.colors(count: 4, tint: nil, start: start, end: end) ?? []).map { srgb($0) })
        #expect(srgbColors(view).last == end, "a colour that shows is the user's own")
    }

    @Test func aViewOnScreenFollowsAChangeOfSurfaceAtOnceAndOnlyPaintsOnce() throws {
        store.showTint(darkTint)
        let view = makeView(on: .solid)
        let window = attach(view)
        // The tap's levels, so the only animation there could be is one the surface change made.
        store.showSpectrum([0.2, 0.4, 0.6, 0.8])
        scheduler.advance(by: .milliseconds(40))
        let solid = colours(view)
        let painted = view.paintCount
        view.surface = glass
        #expect(view.paintCount == painted + 1)
        #expect(colours(view) == expectedColours(.artwork, tint: darkTint, surface: glass))
        #expect(colours(view) != solid)
        #expect(edge(view) == [0.35, 0.35, 0.35, 0.35])
        #expect(view.layer?.sublayers?.allSatisfy { $0.animationKeys() == nil } == true, "nothing eases between two surfaces")
        view.surface = .material
        #expect(edge(view) == [0, 0, 0, 0], "the edge goes when the surface is not glass")
        #expect(colours(view) == expectedColours(.artwork, tint: darkTint, surface: .material))
        window.contentView = nil
    }

    @Test func aTintOfTheGlassIsNoNewSurfaceForTheBars() {
        store.showTint(darkTint)
        let view = makeView(on: .liquidGlass(tinted: false))
        let (painted, colours) = (view.paintCount, colours(view))
        view.surface = .liquidGlass(tinted: true)
        #expect(view.paintCount == painted)
        #expect(self.colours(view) == colours)
        view.surface = .liquidGlass(tinted: true)
        #expect(view.paintCount == painted)
    }

    @Test func aSurfaceChangeDoesNotMoveABar() {
        let view = makeView(on: .solid)
        let window = attach(view)
        store.showSpectrum([0.2, 0.4, 0.6, 0.8])
        scheduler.advance(by: .milliseconds(40))
        let before = heights(view)
        view.surface = glass
        #expect(heights(view) == before)
        window.contentView = nil
    }

    @Test func aBrightCoverIsLeftAloneOnBlackAndDarkenedOnGlass() {
        let yellow = SRGBColor(hex: 0xFFE066)
        store.showTint(ArtworkPalette(primary: yellow, secondary: nil))
        #expect(srgbColors(makeView(on: .solid)).allSatisfy { $0.isClose(to: yellow, tolerance: 1e-6) })
        #expect(srgbColors(makeView(on: .material)).allSatisfy { $0.isClose(to: yellow, tolerance: 1e-6) })
        let onGlass = srgbColors(makeView(on: glass))
        #expect(onGlass.allSatisfy { abs($0.luminance - SpectrumBackdrop.glass.minimumLuminance) < 1e-5 }, "\(onGlass.map(\.luminance))")
        #expect(colours(makeView(on: glass)) == expectedColours(.artwork, tint: ArtworkPalette(primary: yellow, secondary: nil), surface: glass))
    }

    @Test func aCoverThatIsWhiteAndWhiteItselfAreNotDrawnTheSameOnGlass() {
        // The two make the same colours; only the cover's is adjusted.
        store.showTint(ArtworkPalette(primary: .white, secondary: nil))
        let view = makeView(on: glass)
        let window = attach(view)
        #expect(srgbColors(view).allSatisfy { $0 != .white }, "the cover's white is darkened like any other colour on glass")
        store.setSpectrumColors(mode: .white, start: SpectrumColorMode.defaultStart, end: SpectrumColorMode.defaultEnd)
        #expect(srgbColors(view).allSatisfy { $0 == .white }, "the user asked for white")
        #expect(edge(view) == [0.35, 0.35, 0.35, 0.35])
        window.contentView = nil
    }

    // MARK: - On screen

    @Test func aViewInAWindowOfAVisibleNotchCountsAsBarsOnScreen() {
        let view = makeView()
        #expect(store.spectrumViewCount == 0)
        let window = attach(view)
        #expect(store.spectrumViewCount == 1)
        window.contentView = nil
        #expect(store.spectrumViewCount == 0)
    }

    @Test func aHiddenNotchTakesTheBarsOffScreen() {
        let view = makeView()
        let window = attach(view)
        view.isNotchOnScreen = false
        #expect(store.spectrumViewCount == 0)
        view.isNotchOnScreen = true
        #expect(store.spectrumViewCount == 1)
        window.contentView = nil
    }

    @Test func aViewThatLeavesItsWindowStopsListeningToTheColours() {
        let view = makeView()
        let window = attach(view)
        window.contentView = nil
        store.showTint(tint)
        #expect(colours(view) == accent, "off screen nothing follows the store")
    }

    @Test func aViewAtTheEndOfItsLifeLeavesTheCount() {
        var view: SpectrumBarsView? = makeView()
        let window = attach(view!)
        #expect(store.spectrumViewCount == 1)
        window.contentView = nil
        view = nil
        #expect(store.spectrumViewCount == 0)
    }

    @Test func settingTheSameVisibilityTwiceCountsOnce() {
        let view = makeView()
        let window = attach(view)
        view.isNotchOnScreen = true
        view.isNotchOnScreen = true
        #expect(store.spectrumViewCount == 1)
        view.isNotchOnScreen = false
        view.isNotchOnScreen = false
        #expect(store.spectrumViewCount == 0)
        window.contentView = nil
    }

    @Test func offScreenTheTapsBandsDrawNothingAndNothingIsScheduled() {
        let view = makeView()
        let window = attach(view)
        view.isNotchOnScreen = false
        let before = heights(view)
        store.showSpectrum([1, 1, 1, 1])
        store.showSpectrum([0.5, 0.5, 0.5, 0.5])
        scheduler.advance(by: .seconds(5))
        #expect(heights(view) == before)
        #expect(scheduler.pendingCount == 0)
        window.contentView = nil
    }

    @Test func backOnScreenTheBarsShowWhatTheTapDeliveredMeanwhile() {
        let view = makeView()
        let window = attach(view)
        view.isNotchOnScreen = false
        store.showSpectrum([1, 1, 1, 1])
        view.isNotchOnScreen = true
        #expect(heights(view).allSatisfy { abs($0 - 14) < 0.001 })
        window.contentView = nil
    }

    @Test func clicksAndHoversBelongToTheViewItSitsIn() {
        let view = makeView()
        #expect(view.hitTest(CGPoint(x: 5, y: 5)) == nil)
    }
}

@Suite struct NowPlayingStoreSpectrumTests {
    nonisolated final class Flag: @unchecked Sendable {
        nonisolated(unsafe) var isSet = false
    }

    let store = NowPlayingStore(lookUpApp: { _ in nil })

    @Test func newBandsNeverInvalidateAnObservingView() {
        let invalidated = Flag()
        withObservationTracking { _ = store.spectrumBands } onChange: { invalidated.isSet = true }
        store.showSpectrum([0.1, 0.2, 0.3, 0.4])
        #expect(!invalidated.isSet)
        #expect(store.spectrumBands == [0.1, 0.2, 0.3, 0.4])
    }

    @Test func observersHearEveryChangeUntilTheyStop() {
        var heard: [[Float]?] = []
        let stop = store.observeSpectrum { heard.append($0) }
        store.showSpectrum([0.1, 0, 0, 0])
        store.showSpectrum([0.1, 0, 0, 0])
        store.showSpectrum([0.2, 0, 0, 0])
        store.showSpectrum(nil)
        #expect(heard == [[0.1, 0, 0, 0], [0.2, 0, 0, 0], nil])
        stop()
        store.showSpectrum([0.3, 0, 0, 0])
        #expect(heard.count == 3)
    }

    @Test func eachObserverStopsOnItsOwn() {
        var first = 0
        var second = 0
        let stopFirst = store.observeSpectrum { _ in first += 1 }
        _ = store.observeSpectrum { _ in second += 1 }
        stopFirst()
        store.showSpectrum([0.5, 0, 0, 0])
        #expect((first, second) == (0, 1))
    }
}
