import AppKit
import Foundation
import NotchUI
import SwiftUI
import Testing
@testable import NotchUI
@testable import PortsModule

/// What the tab draws on Liquid Glass, read from an offscreen render (glass itself cannot be drawn there, so the content is drawn
/// over a flat light or dark grey that stands in for it). Lightness is the least of red, green and blue: white is 1, black and
/// every saturated colour are low, so a white glyph on light glass shows up as a pixel lighter than the background.
@Suite struct PortsGlassTests {
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
                let image = try #require(renderer.cgImage)
                // Read as sRGB bytes in one go: asking an NSBitmapImageRep for each pixel's colour is far slower.
                let width = image.width, height = image.height
                var bytes = [UInt8](repeating: 0, count: width * height * 4)
                let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
                    guard let context = CGContext(
                        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    ) else { return false }
                    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                    return true
                }
                try #require(drawn)
                var pixels: [Double] = []
                pixels.reserveCapacity(width * height)
                for index in stride(from: 0, to: bytes.count, by: 4) {
                    pixels.append(Double(min(bytes[index], bytes[index + 1], bytes[index + 2])) / 255)
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
        /// Pixels of ink the view draws: at least this many are `reach` or more away from the background.
        let ink: Int
        var reach = 0.3
    }

    /// The tab's area: the notch's open height less the tab bar and the inner padding it adds around the content.
    static let size = CGSize(width: 452, height: PortsModule.tabHeight - NotchTokens.padding - 30)

    static let entries: [PortEntry] = [
        .make(port: 3000, process: .make(pid: 10, name: "node", command: "node server.js --watch")),
        .make(port: 5173, process: .make(pid: 11, name: "node", command: "node vite.js"), addresses: [.loopback4, .loopback6]),
        .make(port: 8000, process: .make(pid: 12, name: "Python", command: "python3 -m http.server 8000"), addresses: [.any4, .any6]),
        .make(port: 5353, proto: .udp, process: .make(pid: 13, name: "dnsd", command: nil), addresses: [.lan]),
    ]

    func tab(
        entries: [PortEntry] = PortsGlassTests.entries, filter: String = "", quick: String = "", probe: PortProbeOutcome? = nil,
        flows: [StopFlow] = [], notice: String? = nil, loaded: Bool = true
    ) -> AnyView {
        let state = PortsState()
        state.entries = entries
        state.hasLoaded = loaded
        state.showUDP = true
        state.filter = filter
        state.quickQuery = quick
        state.probe = probe
        state.notice = notice
        for flow in flows { state.flows[flow.entry.pid] = flow }
        return AnyView(PortsTabView(state: state, actions: .none))
    }

    /// The rows on their own: the tab puts them in a scroll view, which an offscreen render draws as nothing.
    func rows(_ flows: [StopFlow] = [], entries: [PortEntry] = PortsGlassTests.entries) -> AnyView {
        AnyView(PortsRows(entries: entries, flows: Dictionary(uniqueKeysWithValues: flows.map { ($0.entry.pid, $0) }), actions: .none))
    }

    var fixtures: [Fixture] {
        let node = Self.entries[0]
        return [
            Fixture(name: "rows", view: rows(), ink: 1500),
            Fixture(name: "rows with the question", view: rows([StopFlow(entry: node, phase: .confirming)]), ink: 1500),
            Fixture(name: "rows with the offer", view: rows([StopFlow(entry: node, phase: .stillRunning)]), ink: 1500),
            Fixture(name: "rows with a refusal", view: rows([StopFlow(entry: node, phase: .refused(.system))]), ink: 1500),
            Fixture(name: "rows with a failure", view: rows([StopFlow(entry: node, phase: .failed(.stuck))]), ink: 1500),
            Fixture(name: "list", view: tab(), ink: 400),
            Fixture(name: "an owner is answered", view: tab(quick: "3000"), ink: 400),
            Fixture(name: "a free port", view: tab(quick: "4000", probe: PortProbeOutcome(port: 4000, result: .free)), ink: 400),
            Fixture(name: "a port in use that nobody can see", view: tab(quick: "5432", probe: PortProbeOutcome(port: 5432, result: .inUse)), ink: 400),
            Fixture(name: "the question", view: tab(flows: [StopFlow(entry: node, phase: .confirming)]), ink: 400),
            Fixture(name: "the offer", view: tab(flows: [StopFlow(entry: node, phase: .stillRunning)], notice: "Đã dừng Python (cổng 8000)"), ink: 400),
            Fixture(name: "a refusal", view: tab(flows: [StopFlow(entry: node, phase: .refused(.system))]), ink: 400),
            Fixture(name: "nothing matches", view: tab(filter: "zzz"), ink: 300),
            Fixture(name: "nothing listens", view: tab(entries: []), ink: 300),
        ]
    }

    @Test func onLightGlassTheViewsDrawDarkAndNothingWhite() throws {
        for fixture in fixtures {
            let reading = try read(fixture.view, glass: true, scheme: .light, size: Self.size)
            #expect(reading.lighter(than: 0.005) == 0, "\(fixture.name): something is drawn white on light glass")
            #expect(reading.darker(than: fixture.reach) >= fixture.ink, "\(fixture.name): what it draws reads dark")
        }
    }

    @Test func onDarkGlassTheViewsDrawLight() throws {
        for fixture in fixtures {
            let reading = try read(fixture.view, glass: true, scheme: .dark, size: Self.size)
            #expect(reading.lighter(than: fixture.reach) >= fixture.ink, "\(fixture.name): what it draws reads light")
        }
    }

    @Test func onTheClassicNotchTheViewsStayWhiteOnBlackWhateverTheAppearanceIs() throws {
        for fixture in fixtures {
            for scheme in [ColorScheme.dark, .light] {
                let reading = try read(fixture.view, glass: false, scheme: scheme, size: Self.size)
                #expect(reading.lighter(than: fixture.reach) >= fixture.ink, "\(fixture.name) in \(scheme)")
            }
        }
    }
}
