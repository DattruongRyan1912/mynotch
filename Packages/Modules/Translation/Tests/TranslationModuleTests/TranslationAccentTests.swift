import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import TranslationModule

/// Colours nothing in the module draws with, so a pass can only mean that a view took the accent its environment gave it.
private let probeGreen = Color(.sRGB, red: 0, green: 1, blue: 0)

/// The accent the user picked, in every mark of the Translation tab, the dictionary card and the chip beside a selection.
/// The environment is what the notch gives its content; a view that asked for the notch's own purple instead would show it
/// under any other accent. Views are drawn offscreen, never put on a screen.
@Suite struct TranslationAccentTests {
    let fixture = ModuleFixture()

    /// The view over black in the dark scheme, as the notch shows it, drawn by SwiftUI alone: exact colours, but no native controls.
    func bitmap<Content: View>(of view: Content, scale: CGFloat = 2) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark).background(Color.black))
        renderer.scale = scale
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    /// The same drawn by AppKit in a window that is never shown, which is what the tab needs for its text fields. An inactive
    /// window washes colours out a little.
    func hostedBitmap<Content: View>(of view: Content, width: CGFloat, height: CGFloat) -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .dark).background(Color.black).frame(width: width, height: height))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: height), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        window.contentView = nil
        return bitmap
    }

    func count(in bitmap: NSBitmapImageRep, where isMatch: (NSColor) -> Bool) -> Int {
        var matches = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), isMatch(pixel) { matches += 1 }
            }
        }
        return matches
    }

    /// Pixels whose colour is mostly green, as the probe accent draws them, however far text smoothing took them to black.
    func isGreenish(_ pixel: NSColor) -> Bool {
        pixel.greenComponent > 0.4 && pixel.greenComponent > 1.5 * pixel.redComponent && pixel.greenComponent > 1.5 * pixel.blueComponent
    }

    /// The notch's own purple (0.49, 0.36, 1.0) at any brightness. macOS's blue, which a focus ring or a caret may draw, has no
    /// red in it and is not counted.
    func isNotchPurple(_ pixel: NSColor) -> Bool {
        let blue = pixel.blueComponent
        guard blue > 0.35 else { return false }
        return (0.35...0.65).contains(pixel.redComponent / blue) && (0.25...0.5).contains(pixel.greenComponent / blue)
    }

    var source: SelectionSource {
        SelectionSource(text: "Hello", application: FocusedApplication(processID: 42, bundleID: "com.apple.Safari"))
    }

    // MARK: the dictionary card

    @Test func theDictionaryCardsLinkIsDrawnInTheEnvironmentsAccent() throws {
        let entry = DictionaryEntry(term: "run", headword: "run", partOfSpeech: "verb", senses: ["Move at a speed faster than a walk"])
        let card = DictionaryCardView(entry: entry, open: {}).frame(width: 189)
        let drawn = try bitmap(of: card.environment(\.notchAccent, probeGreen))
        #expect(count(in: drawn, where: isGreenish) > 20)
        #expect(count(in: drawn, where: isNotchPurple) == 0, "nothing is left in the notch's own purple")
    }

    // MARK: the tab

    // The tab's three prominent buttons ("Cài đặt…", "Dịch bằng Apple", "Thay vào chỗ đang chọn") take the accent through `.tint`,
    // which the system draws in grey in a window that is not key, so drawn offscreen they cannot tell one accent from another.
    // They are on the by-eye list.

    @Test func theAccessibilityButtonIsFilledWithTheEnvironmentsAccent() async throws {
        await fixture.start()
        // Without the permission the hint stays up when the tab appears and checks.
        fixture.accessibility.isTrusted = false
        fixture.state.input = "Hello"
        fixture.state.output = "Xin chào"
        fixture.state.selectionSource = source
        fixture.state.needsAccessibility = true
        let tab = try #require(fixture.module.makeTab())
        let drawn = hostedBitmap(of: tab.content.environment(\.notchAccent, probeGreen), width: 452, height: 220)
        #expect(count(in: drawn, where: isGreenish) > 40)
        #expect(count(in: drawn, where: isNotchPurple) == 0, "nothing is left in the notch's own purple")
    }

    @Test func theAccessibilityButtonsLabelIsDarkOnALightAccentAndWhiteOnADarkOne() async throws {
        await fixture.start()
        fixture.accessibility.isTrusted = false
        fixture.state.input = "Hello"
        fixture.state.output = "Xin chào"
        fixture.state.selectionSource = source
        fixture.state.needsAccessibility = true
        let tab = try #require(fixture.module.makeTab())
        func whitePixels(under accent: Color) -> Int {
            let drawn = hostedBitmap(of: tab.content.environment(\.notchAccent, accent), width: 452, height: 220)
            return count(in: drawn) { $0.redComponent > 0.9 && $0.greenComponent > 0.9 && $0.blueComponent > 0.9 }
        }
        // The rest of the tab is white under either accent; what differs is "Cấp quyền" on the button.
        let onBlue = whitePixels(under: NotchAccent.Palette.blue.rgb.color)
        let onYellow = whitePixels(under: NotchAccent.Palette.yellow.rgb.color)
        #expect(onBlue > onYellow + 20, "\(onBlue) vs \(onYellow)")
    }

    // MARK: the chip

    func content() -> SelectionChipContent {
        SelectionChipContent(kind: .conversion, text: "5 ft 11 in → 180 cm", open: {}, deny: {}, hover: { _ in })
    }

    @Test func theChipIsDrawnInTheEnvironmentsAccent() throws {
        let drawn = try bitmap(of: SelectionChipLabel(content: content()).environment(\.notchAccent, probeGreen))
        #expect(count(in: drawn, where: isGreenish) > 40)
        #expect(count(in: drawn, where: isNotchPurple) == 0, "nothing is left in the notch's own purple")
    }

    @Test func theChipsOwnPanelTakesTheInterfacesAccentNotWhatItIsPutIn() throws {
        // A panel of its own does not inherit the notch's environment, so the chip hands down the interface's accent, which
        // is the notch's purple until a theme is followed, whatever environment it is put in.
        let interface = NotchInterface()
        let drawn = try bitmap(of: SelectionChipView(content: content(), interface: interface).environment(\.notchAccent, probeGreen))
        #expect(count(in: drawn, where: isNotchPurple) > 40)
        #expect(count(in: drawn, where: isGreenish) == 0)
    }

    @Test func theChipsButtonLabelIsDarkOnALightAccentAndWhiteOnADarkOne() throws {
        func whitePixels(under accent: Color) throws -> Int {
            let drawn = try bitmap(of: SelectionChipLabel(content: content()).environment(\.notchAccent, accent))
            return count(in: drawn) { $0.redComponent > 0.9 && $0.greenComponent > 0.9 && $0.blueComponent > 0.9 }
        }
        // The rest of the chip is white either way; what differs is the "Mở" on the button.
        let onBlue = try whitePixels(under: NotchAccent.Palette.blue.rgb.color)
        let onYellow = try whitePixels(under: NotchAccent.Palette.yellow.rgb.color)
        #expect(onBlue > onYellow + 20, "\(onBlue) vs \(onYellow)")
    }

    // MARK: the label on an accent

    @Test func aLabelStaysReadableOnALightAccent() {
        let white = NotchTokens.primaryText
        // The palette colours as macOS shows them on a dark surface (blue, purple, pink, red) keep the white they always had.
        for accent in [NotchAccent.Palette.blue, .purple, .pink, .red].map(\.rgb.color) {
            #expect(AccentLabel.colour(on: accent) == white)
        }
        // Yellow, orange and green are too light for white to be read on them.
        for accent in [NotchAccent.Palette.yellow, .orange, .green].map(\.rgb.color) {
            #expect(AccentLabel.colour(on: accent) != white)
        }
        // The notch's own purple, the default, keeps white.
        #expect(AccentLabel.colour(on: NotchTokens.accent) == white)
    }
}
