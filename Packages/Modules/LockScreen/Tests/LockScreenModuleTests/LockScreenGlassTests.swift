import AppKit
import Foundation
import MyNotchCore
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import NotchUI
@testable import LockScreenModule

/// What the lock screen's card draw on Liquid Glass, read from an offscreen render (glass itself cannot be drawn there, so the content is
/// drawn over a flat light or dark grey that stands in for it). Lightness is the least of red, green and blue: white is 1, black
/// and every saturated colour are low, so a white glyph on light glass shows up as a pixel lighter than the background.
@Suite struct LockScreenGlassTests {
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

    /// Harnesses of the lock screens the fixtures draw, kept so they outlive the call that made them.
    static var kept: [LockScreenFixture] = []

    /// What the lock screen's window draws while a contributor offers `view`: the card, on the notch's black.
    func card(offering view: some View) async -> AnyView {
        let fixture = LockScreenFixture()
        await fixture.enable()
        fixture.harness.lockScreen.set(AnyView(view), priority: .normal, from: "timer")
        await fixture.lock()
        Self.kept.append(fixture)
        return fixture.factory.windows[0].content
    }

    /// A contributor that draws with the notch's text tokens in its body, as Media's and Battery's views do.
    struct Contributor: View {
        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "timer").foregroundStyle(NotchTokens.secondaryText)
                Text("12:30").font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(NotchTokens.primaryText)
            }
        }
    }

    var fixtures: [Fixture] {
        get async {
            // The card is black on any look, so the text on it is meant to be light, even on light glass.
            [Fixture(name: "card", view: await card(offering: Contributor()), size: CGSize(width: 420, height: 80), wash: nil, ink: 100, reach: 0.15)]
        }
    }

    @Test func theCardKeepsLightTextOnItsBlackSurfaceOnLightGlass() async throws {
        let reading = try read(await card(offering: Contributor()), glass: true, scheme: .light, size: CGSize(width: 420, height: 80))
        #expect(reading.lighter(than: 0.05) >= 100, "the contributor's text is light on the black card, not black on black")
    }
    @Test func onLightGlassTheCardDrawDarkAndNothingWhite() async throws {
        for fixture in await fixtures {
            let reading = try read(fixture.view, glass: true, scheme: .light, size: fixture.size)
            if let wash = fixture.wash {
                #expect(reading.lighter(than: wash) == 0, "\(fixture.name): something is drawn white on light glass")
            }
            #expect(reading.darker(than: fixture.reach) >= fixture.ink, "\(fixture.name): what it draws reads dark")
        }
    }

    @Test func onDarkGlassTheCardDrawLight() async throws {
        for fixture in await fixtures {
            let reading = try read(fixture.view, glass: true, scheme: .dark, size: fixture.size)
            #expect(reading.lighter(than: fixture.reach) >= fixture.ink, "\(fixture.name): what it draws reads light")
        }
    }

    @Test func onTheClassicNotchTheCardStayWhiteOnBlackWhateverTheAppearanceIs() async throws {
        for fixture in await fixtures {
            for scheme in fixture.classicSchemes {
                let reading = try read(fixture.view, glass: false, scheme: scheme, size: fixture.size)
                #expect(reading.lighter(than: fixture.reach) >= fixture.ink, "\(fixture.name) in \(scheme)")
            }
        }
    }
}
