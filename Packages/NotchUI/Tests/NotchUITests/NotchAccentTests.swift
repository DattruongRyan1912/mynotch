import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// The accent the user picks: macOS's own, one of eight, or any colour. What each one resolves to, what is stored, and
/// that a value that cannot be read gives the default back.
@Suite struct NotchAccentTests {
    typealias RGB = NotchAccent.RGB

    let blue = RGB(red: 10, green: 132, blue: 255)
    let red = RGB(red: 255, green: 69, blue: 58)

    // MARK: resolution

    @Test func theSystemAccentIsWhateverMacOSSaysAtThatMoment() {
        #expect(NotchAccent.system.resolved(system: blue) == blue)
        #expect(NotchAccent.system.resolved(system: red) == red)
    }

    @Test func aPaletteColourIsTheSameWhateverTheSystemAccentIs() {
        for palette in NotchAccent.Palette.allCases {
            let accent = NotchAccent.palette(palette)
            #expect(accent.resolved(system: blue) == accent.resolved(system: red), "\(palette)")
            #expect(accent.resolved(system: blue) == palette.rgb)
        }
    }

    @Test func thePaletteHasEightDifferentColoursAndEachOneShowsOnBlack() {
        #expect(NotchAccent.Palette.allCases.count == 8)
        #expect(Set(NotchAccent.Palette.allCases.map(\.rgb)).count == 8)
        for palette in NotchAccent.Palette.allCases {
            #expect(palette.rgb.peak >= NotchAccent.RGB.minimumPeak, "\(palette)")
        }
    }

    @Test func aCustomColourIsKept() {
        let custom = RGB(red: 124, green: 92, blue: 255)
        #expect(NotchAccent.custom(custom).resolved(system: blue) == custom)
        #expect(NotchAccent.custom(custom).resolved(system: red) == custom)
    }

    @Test func aCustomColourTooDarkToSeeOnABlackNotchIsLiftedAndKeepsItsHue() {
        let black = NotchAccent.custom(RGB(red: 0, green: 0, blue: 0)).resolved(system: blue)
        #expect(black.peak == NotchAccent.RGB.minimumPeak)
        #expect(black.red == black.green && black.green == black.blue)
        let navy = NotchAccent.custom(RGB(red: 0, green: 0, blue: 40)).resolved(system: blue)
        #expect(navy == RGB(red: 0, green: 0, blue: NotchAccent.RGB.minimumPeak))
        let brownish = NotchAccent.custom(RGB(red: 40, green: 20, blue: 0)).resolved(system: blue)
        // Scaled together, so a brown stays a brown: 40, 20, 0 at a peak of 102 is 102, 51, 0.
        #expect(brownish == RGB(red: 102, green: 51, blue: 0))
    }

    @Test func aColourThatAlreadyShowsIsNeverChanged() {
        for rgb in [RGB(red: 255, green: 255, blue: 255), RGB(red: 0, green: 0, blue: 255), RGB(red: 102, green: 0, blue: 0)] {
            #expect(NotchAccent.custom(rgb).resolved(system: blue) == rgb)
        }
    }

    // MARK: the system accent

    @Test func theSystemAccentIsTheColourForADarkSurfaceWhateverTheAppearanceOfTheApp() throws {
        // The notch is black in a light appearance too. A colour that differs between the two gives its dark one.
        let accent = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 1, green: 0.4, blue: 0, alpha: 1) : NSColor(srgbRed: 0.5, green: 0, blue: 0, alpha: 1)
        }
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            var seen: RGB?
            try #require(NSAppearance(named: name)).performAsCurrentDrawingAppearance { seen = SystemAccent.current(of: accent) }
            #expect(seen == RGB(red: 255, green: 102, blue: 0), "\(name.rawValue)")
        }
    }

    @Test func theSystemAccentIsMacOSsOwnAndTheSameInEitherAppearance() throws {
        var inLight: RGB?
        var inDark: RGB?
        try #require(NSAppearance(named: .aqua)).performAsCurrentDrawingAppearance { inLight = SystemAccent.current() }
        try #require(NSAppearance(named: .darkAqua)).performAsCurrentDrawingAppearance { inDark = SystemAccent.current() }
        #expect(inLight != nil && inLight == inDark)
    }

    // MARK: from a colour picker

    @Test func aColourFromThePickerBecomesACustomAccent() {
        let accent = NotchAccent(color: Color(.sRGB, red: 0.2, green: 0.4, blue: 0.6))
        #expect(accent == .custom(RGB(red: 51, green: 102, blue: 153)))
    }

    @Test func aColourFromAnotherColourSpaceIsConvertedToSRGB() {
        let accent = NotchAccent(color: Color(nsColor: NSColor(white: 1, alpha: 1)))
        #expect(accent == .custom(RGB(red: 255, green: 255, blue: 255)))
    }

    @Test func anAccentBecomesAColourForThePage() {
        let color = NotchAccent.palette(.green).color
        #expect(NSColor(color).usingColorSpace(.sRGB)?.greenComponent ?? 0 > 0.8)
    }

    // MARK: stored

    @Test func eachAccentIsStoredAsOneShortReadableString() throws {
        func stored(_ accent: NotchAccent) throws -> String {
            String(decoding: try JSONEncoder().encode(accent), as: UTF8.self)
        }
        #expect(try stored(.system) == "\"system\"")
        #expect(try stored(.palette(.blue)) == "\"palette:blue\"")
        #expect(try stored(.custom(RGB(red: 124, green: 92, blue: 255))) == "\"custom:#7C5CFF\"")
        #expect(try stored(.custom(RGB(red: 0, green: 5, blue: 10))) == "\"custom:#00050A\"")
    }

    @Test func whatIsStoredComesBackTheSame() throws {
        for accent in [NotchAccent.system] + NotchAccent.Palette.allCases.map(NotchAccent.palette)
            + [.custom(RGB(red: 1, green: 2, blue: 3)), .custom(RGB(red: 255, green: 255, blue: 255))] {
            let data = try JSONEncoder().encode(accent)
            #expect(try JSONDecoder().decode(NotchAccent.self, from: data) == accent)
        }
    }

    @Test func aCustomColourIsReadInUpperOrLowerCase() throws {
        let lower = try JSONDecoder().decode(NotchAccent.self, from: Data("\"custom:#7c5cff\"".utf8))
        #expect(lower == .custom(RGB(red: 124, green: 92, blue: 255)))
    }

    @Test func aValueNobodyCanReadIsTheDefault() {
        for bad in ["\"mauve\"", "\"palette:teal\"", "\"palette:\"", "\"custom:#12\"", "\"custom:#GGGGGG\"", "\"custom:7C5CFF\"",
                    "\"custom:#7C5CFF00\"", "\"\"", "42", "{\"palette\":{\"_0\":\"blue\"}}", "null"] {
            let defaults = makeIsolatedDefaults()
            defaults.set(Data(bad.utf8), forKey: InterfaceSettings.accent.name)
            #expect(SettingsStore(defaults: defaults).value(InterfaceSettings.accent) == .system, "\(bad)")
        }
    }

    @Test func theChoiceIsKeptForTheNextLaunchAndResetGoesBackToTheSystemAccent() {
        let defaults = makeIsolatedDefaults()
        for accent in [NotchAccent.palette(.pink), .custom(RGB(red: 9, green: 8, blue: 7)), .system] {
            SettingsStore(defaults: defaults).set(accent, for: InterfaceSettings.accent)
            #expect(SettingsStore(defaults: defaults).value(InterfaceSettings.accent) == accent)
        }
        let store = SettingsStore(defaults: defaults)
        store.set(.palette(.red), for: InterfaceSettings.accent)
        store.reset(InterfaceSettings.accent)
        #expect(store.value(InterfaceSettings.accent) == .system)
    }
}
