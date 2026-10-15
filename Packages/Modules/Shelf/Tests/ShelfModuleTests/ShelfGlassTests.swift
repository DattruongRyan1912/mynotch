import AppKit
import Foundation
import NotchUI
import SwiftUI
import Testing
@testable import NotchUI
@testable import ShelfModule

/// What the views draw on Liquid Glass, read from an offscreen render (glass itself cannot be drawn there, so the content is
/// drawn over a flat light or dark grey that stands in for it). Lightness is the least of red, green and blue: white is 1, black
/// and every saturated colour are low, so a white glyph on light glass shows up as a pixel lighter than the background.
@Suite struct ShelfGlassTests {
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

    /// Harnesses of the shelves the fixtures draw, kept so the modules outlive the call that made them.
    static var kept: [ShelfFixture] = []

    /// The Khay tab of a started shelf holding `providers`, as the notch shows it.
    func tab(holding providers: [NSItemProvider]) async -> AnyView {
        let fixture = ShelfFixture()
        await fixture.start()
        _ = await fixture.module.add(providers: providers)
        Self.kept.append(fixture)
        guard let tab = fixture.module.makeTab() else { preconditionFailure("a started module has its tab") }
        return tab.content
    }

    var fixtures: [Fixture] {
        get async {
            let module = ShelfModule()
            let card = ShelfItem(kind: .text("Ghi chú cuộc họp"))
            var report = FileActionRunner.Report(action: .readText)
            report.text = "Nội dung đọc được từ ảnh chụp màn hình"
            report.textCopied = true
            let notes = [NSItemProvider(object: "Ghi chú cuộc họp" as NSString), NSItemProvider(object: URL(string: "https://example.com/a")! as NSURL)]
            let tabSize = CGSize(width: 452, height: 150)
            return [
                // The tab draws with the system's colours and sets the scheme itself, so it is checked in both appearances. The two
                // views drawn alone are not under the tab's scheme, and are checked in the dark appearance only.
                Fixture(name: "empty tab", view: await tab(holding: []), size: tabSize, wash: 0.005, ink: 50, reach: 0.15),
                Fixture(name: "tab with cards", view: await tab(holding: notes), size: tabSize, wash: 0.005, ink: 100, reach: 0.15),
                Fixture(name: "card", view: AnyView(ShelfCardView(item: card, state: module.state, module: module)), size: CGSize(width: 76, height: 78), wash: 0.005, ink: 50, classicSchemes: [.dark]),
                Fixture(name: "report", view: AnyView(ShelfActionReportView(report: report, module: module)), size: CGSize(width: 452, height: 100), wash: 0.005, ink: 100, classicSchemes: [.dark]),
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
