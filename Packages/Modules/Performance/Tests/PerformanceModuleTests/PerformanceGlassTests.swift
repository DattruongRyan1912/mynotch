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
                return Self.lightness(of: try #require(renderer.cgImage))
            }
            // The renderer lifts tones a little, so the background is what an empty picture reads, not the grey that was set.
            return Reading(background: try lightness(of: Color.clear)[0], pixels: try lightness(of: view))
        }
    }

    /// The least of red, green and blue of every pixel, 0 to 1, read from the image redrawn in sRGB: one pass over the bytes, where
    /// asking a bitmap for the colour of each pixel took half a minute for the whole suite.
    static func lightness(of image: CGImage) -> [Double] {
        let (width, height) = (image.width, image.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return stride(from: 0, to: bytes.count, by: 4).map { Double(min(bytes[$0], bytes[$0 + 1], bytes[$0 + 2])) / 255 }
    }

    struct Fixture {
        let name: String
        let view: AnyView
        let size: CGSize
        /// Pixels of ink the view draws: at least this many are `reach` or more away from the background.
        let ink: Int
        var reach = 0.3
    }

    func columns(
        cpu: Double, gpu: Double, fans: Int = 2, thermal: Bool = true, pressure: MemoryPressure? = .normal,
        helper: HelperRig = HelperRig(status: .notRegistered)
    ) async -> AnyView {
        let state = await PerformanceTabLayoutTests.state(fans: fans, thermal: thermal, helper: helper)
        state.thermal?.cpu = cpu
        state.thermal?.gpu = gpu
        state.usage?.pressure = pressure
        return AnyView(PerformanceColumns(state: state))
    }

    func fixtures() async -> [Fixture] {
        let size = CGSize(width: 452, height: PerformanceTabView.contentHeight)
        let running = HelperRig(status: .enabled)
        let approval = HelperRig(status: .requiresApproval, runningApps: [FanHelperManager.macsFanControlBundleID])
        let broken = HelperRig(status: .enabled, pings: [.failure(.timeout)])
        let empty = PerformanceState()
        empty.hasThermal = true
        return [
            Fixture(name: "normal", view: await columns(cpu: 52, gpu: 48), size: size, ink: 300),
            Fixture(name: "warm", view: await columns(cpu: 78, gpu: 66, pressure: .warning), size: size, ink: 300),
            Fixture(name: "hot", view: await columns(cpu: 96, gpu: 90, pressure: .critical), size: size, ink: 300),
            Fixture(name: "no fans", view: await columns(cpu: 60, gpu: 55, fans: 0), size: size, ink: 300),
            Fixture(name: "memory only", view: await columns(cpu: 0, gpu: 0, thermal: false), size: size, ink: 200),
            Fixture(name: "pressure unknown", view: await columns(cpu: 60, gpu: 55, pressure: nil), size: size, ink: 300),
            Fixture(name: "helper running", view: await columns(cpu: 60, gpu: 55, helper: running), size: size, ink: 300),
            Fixture(name: "helper needs approval and Macs Fan Control runs", view: await columns(cpu: 60, gpu: 55, helper: approval), size: size, ink: 300),
            Fixture(name: "helper unreachable", view: await columns(cpu: 60, gpu: 55, helper: broken), size: size, ink: 300),
            Fixture(name: "nothing read yet", view: AnyView(PerformanceColumns(state: empty)), size: size, ink: 100),
        ]
    }

    @Test func onLightGlassTheViewsDrawDarkAndNothingWhite() async throws {
        for fixture in await fixtures() {
            let reading = try read(fixture.view, glass: true, scheme: .light, size: fixture.size)
            #expect(reading.lighter(than: 0.005) == 0, "\(fixture.name): something is drawn white on light glass")
            #expect(reading.darker(than: fixture.reach) >= fixture.ink, "\(fixture.name): what it draws reads dark")
        }
    }

    @Test func onDarkGlassTheViewsDrawLight() async throws {
        for fixture in await fixtures() {
            let reading = try read(fixture.view, glass: true, scheme: .dark, size: fixture.size)
            #expect(reading.lighter(than: fixture.reach) >= fixture.ink, "\(fixture.name): what it draws reads light")
        }
    }

    @Test func onTheClassicNotchTheViewsStayWhiteOnBlackWhateverTheAppearanceIs() async throws {
        for fixture in await fixtures() {
            for scheme in [ColorScheme.dark, .light] {
                let reading = try read(fixture.view, glass: false, scheme: scheme, size: fixture.size)
                #expect(reading.lighter(than: fixture.reach) >= fixture.ink, "\(fixture.name) in \(scheme)")
            }
        }
    }

    @Test func theTonesAreColoursNotGreys() {
        for tone in [Tone.normal, .caution, .critical] {
            let colour = NSColor(tone.color).usingColorSpace(.sRGB)
            let channels = [colour?.redComponent ?? 0, colour?.greenComponent ?? 0, colour?.blueComponent ?? 0]
            #expect((channels.max() ?? 0) - (channels.min() ?? 0) > 0.5, "\(tone)")
        }
    }
}
