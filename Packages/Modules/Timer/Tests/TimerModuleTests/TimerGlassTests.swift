import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import NotchUI
@testable import TimerModule

/// What the tab draws on Liquid Glass, read from an offscreen render (glass itself cannot be drawn there, so the content is
/// drawn over a flat light or dark grey that stands in for it). Lightness is the least of red, green and blue: white is 1, black
/// and every saturated colour are low, so a white glyph on light glass shows up as a pixel lighter than the background.
@Suite struct TimerGlassTests {
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
            let content = view.frame(width: size.width, height: size.height).background(Color(.sRGB, white: shade)).environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 1
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            var pixels: [Double] = []
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let colour = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    pixels.append(Double(min(colour.redComponent, colour.greenComponent, colour.blueComponent)))
                }
            }
            // The renderer lifts tones a little, so the background is what most of the picture reads, not the grey set.
            return Reading(background: pixels.sorted()[pixels.count / 2], pixels: pixels)
        }
    }

    struct Fixture {
        let name: String
        let view: AnyView
        let size: CGSize
        /// How far above the background a pixel may be on light glass: a system button lifts its own fill a little.
        let wash: Double
        /// Pixels of ink the view draws: at least this many are far from the background.
        let ink: Int
    }

    var fixtures: [Fixture] {
        let module = TimerModule()
        let countdown = TimerState()
        countdown.model = .countdownPaused(remaining: 754)
        let stopwatch = TimerState()
        stopwatch.model = .stopwatchPaused(accumulated: 65)
        let tab = CGSize(width: 452, height: 170)
        return [
            Fixture(name: "countdown", view: AnyView(TimerTabView(state: countdown, module: module)), size: tab, wash: 0.04, ink: 250),
            Fixture(name: "stopwatch", view: AnyView(TimerTabView(state: stopwatch, module: module)), size: tab, wash: 0.04, ink: 250),
            Fixture(name: "dial", view: AnyView(DialRing(fraction: 0.4, tint: .blue, showsKnob: true)), size: CGSize(width: 112, height: 112), wash: 0.005, ink: 100),
        ]
    }

    @Test func onLightGlassTheTabDrawsDarkAndNothingWhite() throws {
        for fixture in fixtures {
            let reading = try read(fixture.view, glass: true, scheme: .light, size: fixture.size)
            #expect(reading.lighter(than: fixture.wash) == 0, "\(fixture.name): something is drawn white on light glass")
            #expect(reading.darker(than: 0.3) >= fixture.ink, "\(fixture.name): the text and the dial read dark")
        }
    }

    @Test func onDarkGlassTheTabDrawsLight() throws {
        for fixture in fixtures {
            let reading = try read(fixture.view, glass: true, scheme: .dark, size: fixture.size)
            #expect(reading.lighter(than: 0.3) >= fixture.ink, "\(fixture.name): the text and the dial read light")
        }
    }

    @Test func onTheClassicNotchTheTabStaysWhiteOnBlackWhateverTheAppearanceIs() throws {
        for fixture in fixtures {
            for scheme in [ColorScheme.dark, .light] {
                let reading = try read(fixture.view, glass: false, scheme: scheme, size: fixture.size)
                #expect(reading.lighter(than: 0.3) >= fixture.ink, "\(fixture.name) in \(scheme)")
                #expect(reading.pixels.max() ?? 0 > 0.95, "\(fixture.name) in \(scheme): white, not a grey")
            }
        }
    }
}
