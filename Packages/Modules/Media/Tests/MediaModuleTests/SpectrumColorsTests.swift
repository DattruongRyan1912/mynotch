import Foundation
import Observation
import Testing
@testable import MediaModule

@Suite struct SpectrumColorModeTests {
    let start = SRGBColor(red: 1, green: 0, blue: 0)
    let end = SRGBColor(red: 0, green: 0, blue: 1)
    let tint = ArtworkPalette(primary: SRGBColor(red: 0.8, green: 0.2, blue: 0), secondary: SRGBColor(red: 0, green: 0.4, blue: 0.8))

    func colors(_ mode: SpectrumColorMode, tint: ArtworkPalette?, count: Int = 4) -> [SRGBColor]? {
        mode.colors(count: count, tint: tint, start: start, end: end)
    }

    @Test func theCoverSpreadsItsTwoColoursAlongTheBars() throws {
        let bars = try #require(colors(.artwork, tint: tint))
        #expect(bars.count == 4)
        #expect(bars.first == tint.primary)
        #expect(bars.last == tint.secondary)
        // Steady steps from the first colour to the second.
        let expected = (0..<4).map { tint.primary.mixed(with: tint.secondary!, amount: Double($0) / 3) }
        #expect(bars == expected)
    }

    @Test func aCoverWithOneColourMakesEveryBarThatColour() throws {
        let one = ArtworkPalette(primary: tint.primary, secondary: nil)
        #expect(colors(.artwork, tint: one) == Array(repeating: tint.primary, count: 4))
    }

    @Test func withoutATintTheCoverModeLeavesTheBarsTheirOwnColour() {
        #expect(colors(.artwork, tint: nil) == nil)
    }

    @Test func whiteIsWhiteWhateverTheCoverSays() {
        let white = SRGBColor(red: 1, green: 1, blue: 1)
        #expect(colors(.white, tint: tint) == Array(repeating: white, count: 4))
        #expect(colors(.white, tint: nil) == Array(repeating: white, count: 4))
    }

    @Test func theGradientRunsFromTheFirstPickerToTheSecondAndIgnoresTheCover() throws {
        let bars = try #require(colors(.gradient, tint: tint))
        #expect(bars == (0..<4).map { start.mixed(with: end, amount: Double($0) / 3) })
        #expect(bars.first == start && bars.last == end)
        #expect(colors(.gradient, tint: nil) == bars)
    }

    @Test func oneBarTakesTheFirstColourAndNoBarsGiveNothing() {
        #expect(colors(.gradient, tint: nil, count: 1) == [start])
        #expect(colors(.artwork, tint: tint, count: 1) == [tint.primary])
        #expect(colors(.gradient, tint: nil, count: 0) == [])
    }

    @Test func theNamesStoredInTheSettingsNeverChange() throws {
        #expect(SpectrumColorMode.allCases.map(\.rawValue) == ["artwork", "white", "gradient"])
        for mode in SpectrumColorMode.allCases {
            let data = try JSONEncoder().encode(mode)
            #expect(try JSONDecoder().decode(SpectrumColorMode.self, from: data) == mode)
        }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(SpectrumColorMode.self, from: Data(#""rainbow""#.utf8)) }
    }

    @Test func theChoicesAreNamedInVietnamese() {
        #expect(SpectrumColorMode.allCases.map(\.title) == ["Theo ảnh bìa", "Trắng", "Gradient"])
    }
}

@Suite struct NowPlayingStoreTintTests {
    nonisolated final class Flag: @unchecked Sendable {
        nonisolated(unsafe) var isSet = false
    }

    let store = NowPlayingStore(lookUpApp: { _ in nil })
    let palette = ArtworkPalette(primary: SRGBColor(red: 0.9, green: 0.3, blue: 0.1), secondary: SRGBColor(red: 0.1, green: 0.5, blue: 0.9))

    @Test func theTintIsOnAndFollowsTheCoverFromTheStart() {
        #expect(store.tintEnabled)
        #expect(store.spectrumMode == .artwork)
        #expect(store.activeTint == nil)
        #expect(store.spectrumColors == nil, "no cover yet: the bars keep their own colour")
    }

    @Test func aTintIsUsedWhileTheSettingIsOn() {
        store.showTint(palette)
        #expect(store.activeTint == palette)
        #expect(store.spectrumColors?.first == palette.primary)
        store.setTintEnabled(false)
        #expect(store.activeTint == nil, "the player's views show nothing of it")
        #expect(store.tint == palette, "kept, so switching it on again is at once")
        store.setTintEnabled(true)
        #expect(store.activeTint == palette)
    }

    @Test func withTheTintOffTheCoverModeFallsBackToTheBarsOwnColour() {
        store.showTint(palette)
        store.setTintEnabled(false)
        #expect(store.spectrumColors == nil)
    }

    @Test func whiteAndGradientDoNotNeedTheTint() {
        let start = SRGBColor(red: 1, green: 0, blue: 0)
        let end = SRGBColor(red: 0, green: 1, blue: 0)
        store.setTintEnabled(false)
        store.setSpectrumColors(mode: .white, start: start, end: end)
        #expect(store.spectrumColors == Array(repeating: SRGBColor(red: 1, green: 1, blue: 1), count: 4))
        store.setSpectrumColors(mode: .gradient, start: start, end: end)
        #expect(store.spectrumColors?.first == start)
        #expect(store.spectrumColors?.last == end)
    }

    @Test func resettingForgetsTheTintButKeepsTheUsersChoices() {
        let start = SRGBColor(red: 1, green: 0, blue: 0)
        let end = SRGBColor(red: 0, green: 1, blue: 0)
        store.showTint(palette)
        store.setTintEnabled(false)
        store.setSpectrumColors(mode: .gradient, start: start, end: end)
        store.reset()
        #expect(store.tint == nil)
        #expect(!store.tintEnabled)
        #expect(store.spectrumMode == .gradient)
        #expect(store.spectrumColors?.first == start)
    }

    @Test func observersOfTheColoursHearEachChangeOnceAndNeverARepeat() {
        var heard: [[SRGBColor]?] = []
        let stop = store.observeSpectrumColors { heard.append($0) }
        store.showTint(palette)
        store.showTint(palette)
        let first = store.spectrumColors
        #expect(heard == [first])
        store.setTintEnabled(false)
        #expect(heard == [first, nil])
        store.setTintEnabled(false)
        store.showTint(nil)
        #expect(heard == [first, nil], "a tint that is off and goes away changes no colour")
        stop()
        store.setTintEnabled(true)
        store.showTint(palette)
        #expect(heard.count == 2)
    }

    @Test func aChangeOfModeOrOfTheGradientIsHeardToo() {
        var heard: [[SRGBColor]?] = []
        _ = store.observeSpectrumColors { heard.append($0) }
        let red = SRGBColor(red: 1, green: 0, blue: 0)
        let blue = SRGBColor(red: 0, green: 0, blue: 1)
        store.setSpectrumColors(mode: .white, start: red, end: blue)
        store.setSpectrumColors(mode: .gradient, start: red, end: blue)
        store.setSpectrumColors(mode: .gradient, start: red, end: red)
        #expect(heard.count == 3)
        #expect(heard.last??.last == red)
    }

    @Test func readingTheColoursRegistersNoDependencyWithSwiftUI() {
        // `makeNSView` of the bars reads them while SwiftUI tracks what it reads; a tracked read would lay the notch out
        // again at every new cover.
        let flag = Flag()
        withObservationTracking { _ = store.spectrumColors } onChange: { flag.isSet = true }
        store.showTint(palette)
        store.setSpectrumColors(mode: .white, start: SRGBColor(red: 1, green: 0, blue: 0), end: SRGBColor(red: 0, green: 0, blue: 1))
        #expect(!flag.isSet)
    }

    @Test func theTintItselfIsObservableForTheViewsThatDrawIt() {
        let flag = Flag()
        withObservationTracking { _ = store.activeTint } onChange: { flag.isSet = true }
        store.showTint(palette)
        #expect(flag.isSet)

        let same = Flag()
        withObservationTracking { _ = store.activeTint } onChange: { same.isSet = true }
        store.showTint(palette)
        #expect(!same.isSet, "the same colours again change nothing")
    }

    @Test func theTabsViewsAreNotInvalidatedByTheTapsBands() {
        store.showTint(palette)
        let flag = Flag()
        withObservationTracking { _ = store.activeTint } onChange: { flag.isSet = true }
        store.showSpectrum([0.1, 0.2, 0.3, 0.4])
        #expect(!flag.isSet)
    }
}
