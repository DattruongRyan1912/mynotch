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

    @Test func thePaletteHasEightDifferentColoursAndEachOneShowsOnBlackAsItIs() {
        #expect(NotchAccent.Palette.allCases.count == 8)
        #expect(Set(NotchAccent.Palette.allCases.map(\.rgb)).count == 8)
        for palette in NotchAccent.Palette.allCases {
            #expect(palette.rgb.selectionContrast >= NotchAccent.RGB.minimumSelectionContrast, "\(palette)")
            #expect(palette.rgb.legibleOnBlack == palette.rgb, "\(palette)")
        }
    }

    @Test func aCustomColourIsKept() {
        let custom = RGB(red: 124, green: 92, blue: 255)
        #expect(NotchAccent.custom(custom).resolved(system: blue) == custom)
        #expect(NotchAccent.custom(custom).resolved(system: red) == custom)
    }

    @Test func aCustomColourTooDarkForTheSelectionToShowOnABlackNotchIsLifted() {
        for dark in [RGB(red: 0, green: 0, blue: 0), RGB(red: 0, green: 0, blue: 40), RGB(red: 0, green: 0, blue: 102), RGB(red: 0, green: 0, blue: 255),
                     RGB(red: 40, green: 20, blue: 0), RGB(red: 30, green: 0, blue: 30), RGB(red: 102, green: 0, blue: 0)] {
            #expect(dark.selectionContrast < NotchAccent.RGB.minimumSelectionContrast, "\(dark) is a case for the rule")
            let lifted = NotchAccent.custom(dark).resolved(system: blue)
            #expect(lifted.selectionContrast >= NotchAccent.RGB.minimumSelectionContrast, "\(dark) -> \(lifted)")
            #expect(lifted.red >= dark.red && lifted.green >= dark.green && lifted.blue >= dark.blue, "\(dark) -> \(lifted)")
        }
    }

    @Test func aLiftedColourStaysTheSameKindOfColour() {
        // Black has no hue and becomes a grey; a dark blue stays blue, a dark red stays red.
        let black = NotchAccent.custom(RGB(red: 0, green: 0, blue: 0)).resolved(system: blue)
        #expect(black.red == black.green && black.green == black.blue)
        let navy = NotchAccent.custom(RGB(red: 0, green: 0, blue: 40)).resolved(system: blue)
        #expect(navy.blue > navy.red && navy.blue > navy.green)
        let maroon = NotchAccent.custom(RGB(red: 60, green: 0, blue: 0)).resolved(system: blue)
        #expect(maroon.red > maroon.green && maroon.red > maroon.blue)
    }

    @Test func aColourThatAlreadyShowsIsNeverChanged() {
        for rgb in [RGB(red: 255, green: 255, blue: 255), RGB(red: 124, green: 92, blue: 255), NotchAccent.Palette.yellow.rgb,
                    NotchAccent.Palette.orange.rgb, RGB(red: 255, green: 0, blue: 0)] {
            #expect(rgb.selectionContrast >= NotchAccent.RGB.minimumSelectionContrast, "\(rgb)")
            #expect(NotchAccent.custom(rgb).resolved(system: blue) == rgb)
        }
    }

    @Test func noColourAtAllIsLeftInvisibleAndLiftingTwiceChangesNothingMore() {
        for red in stride(from: 0, through: 255, by: 17) {
            for green in stride(from: 0, through: 255, by: 17) {
                for blue in stride(from: 0, through: 255, by: 17) {
                    let rgb = RGB(red: UInt8(red), green: UInt8(green), blue: UInt8(blue))
                    let lifted = rgb.legibleOnBlack
                    #expect(lifted.selectionContrast >= NotchAccent.RGB.minimumSelectionContrast, "\(rgb)")
                    #expect(lifted.legibleOnBlack == lifted, "\(rgb)")
                    #expect(lifted.red >= rgb.red && lifted.green >= rgb.green && lifted.blue >= rgb.blue, "\(rgb)")
                }
            }
        }
    }

    // MARK: the cheap ways to a colour

    @Test func aColourForLayersAndAppKitIsTheSameColourInSRGB() throws {
        let rgb = RGB(red: 48, green: 209, blue: 88)
        let srgb = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let converted = try #require(rgb.cgColor.converted(to: srgb, intent: .defaultIntent, options: nil))
        let components = try #require(converted.components)
        #expect(components.count == 4)
        let expected: [CGFloat] = [48.0 / 255, 209.0 / 255, 88.0 / 255, 1]
        for (component, wanted) in zip(components, expected) {
            #expect(abs(component - wanted) < 0.001)
        }
        let ns = try #require(rgb.nsColor.usingColorSpace(.sRGB))
        #expect(abs(ns.greenComponent - 209.0 / 255) < 0.001)
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
