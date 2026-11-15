import AppKit
import Foundation
import NotchUI
import SwiftUI
import Testing
@testable import NotchUI
@testable import ShortcutsModule

/// What the views draw on Liquid Glass, read from an offscreen render (glass itself cannot be drawn there, so the content is
/// drawn over a flat light or dark grey that stands in for it). Lightness is the least of red, green and blue: white is 1, black
/// and every saturated colour are low, so a white glyph on light glass shows up as a pixel lighter than the background.
@Suite struct ShortcutsGlassTests {
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
        /// How far above the background a pixel may be on light glass: a system control lifts its own fill a little.
        let wash: Double
        /// Pixels of ink the view draws: at least this many are `reach` or more away from the background.
        let ink: Int
        var reach = 0.3
    }

    var fixtures: [Fixture] {
        // A module that has not started has no favourites, which is the tab's message.
        let module = ShortcutsModule(cli: FakeShortcutsCLI(), pasteboard: NSPasteboard(name: .init("MyNotchTests.\(UUID().uuidString)")))
        let button = ShortcutInfo(id: "AAAAAAAA-1111-2222-3333-444444444444", name: "Gửi báo cáo")
        return [
            Fixture(name: "no favourites", view: AnyView(ShortcutsTabView(module: module)), size: CGSize(width: 452, height: 106), wash: 0.005, ink: 150),
            Fixture(name: "button", view: AnyView(ShortcutButton(shortcut: button, isRunning: false) {}), size: CGSize(width: 140, height: 34), wash: 0.005, ink: 50),
            Fixture(name: "activity text", view: AnyView(ShortcutActivityText(text: "Đã chạy Gửi báo cáo")), size: CGSize(width: 120, height: 30), wash: 0.005, ink: 50),
            Fixture(name: "output toast", view: AnyView(ShortcutOutputToast(text: "Đã gửi 3 tệp", copy: {})), size: CGSize(width: 452, height: 50), wash: 0.04, ink: 100),
        ]
    }
    @Test func onLightGlassTheViewsDrawDarkAndNothingWhite() throws {
        for fixture in fixtures {
            let reading = try read(fixture.view, glass: true, scheme: .light, size: fixture.size)
            #expect(reading.lighter(than: fixture.wash) == 0, "\(fixture.name): something is drawn white on light glass")
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
}
