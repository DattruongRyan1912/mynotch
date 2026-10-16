import AppKit
import Foundation
import NotchUI
import SwiftUI
import Testing
@testable import NotchUI
@testable import PerformanceModule

/// What the views draw on Liquid Glass, read from an offscreen render (glass itself cannot be drawn there, so the content is
/// drawn over a flat light or dark grey that stands in for it). Lightness is the least of red, green and blue: white is 1, black
/// and every saturated colour are low, so a white glyph on light glass shows up as a pixel lighter than the background.
@Suite struct PerformanceGlassTests {
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
        /// Pixels of ink the view draws: at least this many are `reach` or more away from the background.
        let ink: Int
        var reach = 0.3
    }

    func column(cpu: Double, gpu: Double, fans: Int = 2) -> AnyView {
        let state = PerformanceTabLayoutTests.state(fans: fans)
        state.thermal?.cpu = cpu
        state.thermal?.gpu = gpu
        return AnyView(ThermalColumn(state: state))
    }

    var fixtures: [Fixture] {
        let size = CGSize(width: 452, height: PerformanceTabView.contentHeight)
        return [
            Fixture(name: "normal", view: column(cpu: 52, gpu: 48), size: size, ink: 150),
            Fixture(name: "warm", view: column(cpu: 78, gpu: 66), size: size, ink: 150),
            Fixture(name: "hot", view: column(cpu: 96, gpu: 90), size: size, ink: 150),
            Fixture(name: "no fans", view: column(cpu: 60, gpu: 55, fans: 0), size: size, ink: 150),
            Fixture(name: "nothing read yet", view: AnyView(ThermalColumn(state: PerformanceState())), size: size, ink: 100),
        ]
    }

    @Test func onLightGlassTheViewsDrawDarkAndNothingWhite() throws {
        for fixture in fixtures {
            let reading = try read(fixture.view, glass: true, scheme: .light, size: fixture.size)
            #expect(reading.lighter(than: 0.005) == 0, "\(fixture.name): something is drawn white on light glass")
            #expect(reading.darker(than: fixture.reach) >= fixture.ink, "\(fixture.name): what it draws reads dark")
        }
    }

    @Test func onDarkGlassTheViewsDrawLight() throws {
        for fixture in fixtures {
            let reading = try read(fixture.view, glass: true, scheme: .dark, size: fixture.size)
            #expect(reading.lighter(than: fixture.reach) >= fixture.ink, "\(fixture.name): what it draws reads light")
        }
    }

    @Test func onTheClassicNotchTheViewsStayWhiteOnBlackWhateverTheAppearanceIs() throws {
        for fixture in fixtures {
            for scheme in [ColorScheme.dark, .light] {
                let reading = try read(fixture.view, glass: false, scheme: scheme, size: fixture.size)
                #expect(reading.lighter(than: fixture.reach) >= fixture.ink, "\(fixture.name) in \(scheme)")
            }
        }
    }

    @Test func theTonesAreColoursNotGreys() {
        for tone in [TemperatureTone.normal, .warm, .hot] {
            let colour = NSColor(tone.color).usingColorSpace(.sRGB)
            let channels = [colour?.redComponent ?? 0, colour?.greenComponent ?? 0, colour?.blueComponent ?? 0]
            #expect((channels.max() ?? 0) - (channels.min() ?? 0) > 0.5, "\(tone)")
        }
    }
}
