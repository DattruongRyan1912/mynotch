import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import NotchUI
@testable import TranslationModule

/// What the views draw on Liquid Glass, read from an offscreen render (glass itself cannot be drawn there, so the content is
/// drawn over a flat light or dark grey that stands in for it). Lightness is the least of red, green and blue: white is 1, black
/// and every saturated colour are low, so a white glyph on light glass shows up as a pixel lighter than the background.
@Suite struct TranslationGlassTests {
    struct Reading {
        let background: Double
        let pixels: [Double]
        func lighter(than margin: Double) -> Int { pixels.filter { $0 > background + margin }.count }
        func darker(than margin: Double) -> Int { pixels.filter { $0 < background - margin }.count }
    }

    func read(_ view: some View, glass: Bool, scheme: ColorScheme, size: CGSize) throws -> Reading {
        let state = NotchLookState()
        state.isGlass = glass
        let shade = !glass ? 0.0 : scheme == .light ? 0.75 : 0.15
        return try NotchLookState.$current.withValue(state) {
            @MainActor func lightness(of view: some View) throws -> [Double] {
                let content = view.frame(width: size.width, height: size.height).background(Color(.sRGB, white: shade))
                    .environment(\.colorScheme, scheme)
                    .environment(\.notchSurface, glass ? .liquidGlass(tinted: false) : .solid)
                let host = NSHostingView(rootView: content)
                host.frame = CGRect(origin: .zero, size: size)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                // AppKit controls follow the window's appearance, not SwiftUI's colour scheme.
                window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4,
                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                bitmap.size = size
                host.cacheDisplay(in: host.bounds, to: bitmap)
                var pixels: [Double] = []
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        let colour = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        pixels.append(Double(min(colour.redComponent, colour.greenComponent, colour.blueComponent)))
                    }
                }
                return pixels
            }
            // The renderer lifts tones a little, so the background is what an empty picture reads, not the grey that was set.
            return Reading(background: try lightness(of: Color.clear)[0], pixels: try lightness(of: view))
        }
    }

    struct Fixture {
        let name: String
        let view: AnyView
        let size: CGSize
        /// How far above the background a pixel may be on light glass: a system control lifts its own fill a little. Nil where
        /// the view draws light on a dark fill of its own on purpose.
        let wash: Double?
        /// Pixels of ink the view draws: at least this many are `reach` or more away from the background.
        let ink: Int
        var reach = 0.3
        /// The appearances the classic notch is checked in: a view that draws with the system's colours has only the dark one.
        var classicSchemes: [ColorScheme] = [.dark, .light]
    }

    /// Harness of the module a fixture draws, kept so the module outlives the call that made it.
    static var kept: [ModuleFixture] = []

    func tab(_ configure: (TranslationState) -> Void) async -> AnyView {
        let fixture = ModuleFixture()
        await fixture.start()
        fixture.state.target = .vi
        fixture.state.source = .en
        configure(fixture.state)
        Self.kept.append(fixture)
        guard let tab = fixture.module.makeTab() else { preconditionFailure("a started module has its tab") }
        return tab.content
    }

    func chip(_ kind: SelectionHint.Kind, text: String) -> AnyView {
        let content = SelectionChipContent(kind: kind, text: text, open: {}, hover: { _ in })
        return AnyView(SelectionChipView(content: content, interface: NotchInterface()))
    }


    func inputField(onGlass: Bool) -> AnyView {
        AnyView(TranslationInputField(text: "Hello, how are you today?", focusRequest: 0, onEdit: { _ in }, onSubmit: { _ in }, onGlass: onGlass))
    }

    @Test func theInputFieldIsWhiteOnADarkScrollerOnTheClassicNotchAndTheSystemsOnGlass() {
        let classic = TranslationInputField.Look(onGlass: false)
        #expect(classic.textColor == .white)
        #expect(classic.appearance == .darkAqua)
        let glass = TranslationInputField.Look(onGlass: true)
        #expect(glass.textColor == .labelColor)
        #expect(glass.appearance == nil)
    }

    @Test func theInputFieldsTextReadsDarkOnLightGlassAndLightOnDarkGlassAndWhiteOnTheClassicNotch() async throws {
        let size = CGSize(width: 240, height: 40)
        let onLight = try read(inputField(onGlass: true), glass: true, scheme: .light, size: size)
        #expect(onLight.darker(than: 0.3) >= 100)
        let onDark = try read(inputField(onGlass: true), glass: true, scheme: .dark, size: size)
        #expect(onDark.lighter(than: 0.3) >= 100)
        let classic = try read(inputField(onGlass: false), glass: false, scheme: .light, size: size)
        #expect(classic.lighter(than: 0.3) >= 100, "white even in a light appearance")
    }

    @Test func aLabelOnTheAccentIsWhiteOnGlassToo() {
        let glass = NotchLookState()
        glass.isGlass = true
        NotchLookState.$current.withValue(glass) {
            #expect(AccentLabel.colour(on: NotchTokens.accent) == Color.white)
        }
    }

    @Test func theChipKeepsLightTextOnItsBlackSurfaceOnLightGlass() async throws {
        let reading = try read(chip(.conversion, text: "5 ft 11 in = 1,80 m"), glass: true, scheme: .light, size: CGSize(width: 300, height: 40))
        #expect(reading.lighter(than: 0.05) >= 50, "light text and a white label on the chip, not black on black")
    }

    @Test func theChipsKeepALightIconAndTheTextStaysDarkOnLightGlass() async throws {
        let result = await tab {
            $0.input = "Hello, how are you today?"
            $0.output = "Xin chào, hôm nay bạn thế nào?"
        }
        let reading = try read(result, glass: true, scheme: .light, size: CGSize(width: 452, height: 176))
        #expect(reading.lighter(than: 0.05) >= 5, "a light icon on each black chip, not a black one")
        // Nothing else is light: the text of both boxes, the input field's included, is dark on light glass.
        #expect(reading.lighter(than: 0.05) <= 60)
    }

    var fixtures: [Fixture] {
        get async {
            let tab = CGSize(width: 452, height: 176)
            let empty = await self.tab { _ in }
            let dictionary = await self.tab {
                $0.dictionary = DictionaryEntry(term: "run", headword: "run", partOfSpeech: "động từ", senses: ["chạy", "điều hành"])
                $0.error = "Không dịch được"
            }
            let result = await self.tab {
                $0.input = "Hello, how are you today?"
                $0.output = "Xin chào, hôm nay bạn thế nào?"
            }
            let conversion = await self.tab {
                $0.input = "72 °F"
                $0.conversions = [Conversion(source: "72 °F", outcome: .lines([ConversionLine(text: "22,2 °C")]))]
                $0.showsConversionsOnly = true
            }
            return [
                Fixture(name: "empty", view: empty, size: tab, wash: 0.005, ink: 100, reach: 0.15),
                Fixture(name: "dictionary and error", view: dictionary, size: tab, wash: 0.005, ink: 100, reach: 0.15),
                // Light icons on the black chips beside the text are meant to be light, so these two cannot be held to "nothing white".
                Fixture(name: "result", view: result, size: tab, wash: nil, ink: 100, reach: 0.15),
                Fixture(name: "conversion", view: conversion, size: tab, wash: nil, ink: 100, reach: 0.15),
                Fixture(name: "chip", view: chip(.conversion, text: "5 ft 11 in = 1,80 m"), size: CGSize(width: 300, height: 40), wash: nil, ink: 100, reach: 0.15),
            ]
        }
    }
    @Test func onLightGlassTheViewsDrawDarkAndNothingWhite() async throws {
        for fixture in await fixtures {
            let reading = try read(fixture.view, glass: true, scheme: .light, size: fixture.size)
            if let wash = fixture.wash {
                #expect(reading.lighter(than: wash) == 0, "\(fixture.name): something is drawn white on light glass")
            }
            #expect(reading.darker(than: fixture.reach) >= fixture.ink, "\(fixture.name): what it draws reads dark")
        }
    }

    @Test func onDarkGlassTheViewsDrawLight() async throws {
        for fixture in await fixtures {
            let reading = try read(fixture.view, glass: true, scheme: .dark, size: fixture.size)
            #expect(reading.lighter(than: fixture.reach) >= fixture.ink, "\(fixture.name): what it draws reads light")
        }
    }

    @Test func onTheClassicNotchTheViewsStayWhiteOnBlackWhateverTheAppearanceIs() async throws {
        for fixture in await fixtures {
            for scheme in fixture.classicSchemes {
                let reading = try read(fixture.view, glass: false, scheme: scheme, size: fixture.size)
                #expect(reading.lighter(than: fixture.reach) >= fixture.ink, "\(fixture.name) in \(scheme)")
            }
        }
    }
}
