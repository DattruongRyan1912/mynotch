import AppKit
import Foundation
import NotchUI
import SwiftUI
import Testing
@testable import NotchUI
@testable import BatteryModule

/// What the views draw on Liquid Glass, read from an offscreen render (glass itself cannot be drawn there, so the content is
/// drawn over a flat light or dark grey that stands in for it). Lightness is the least of red, green and blue: white is 1, black
/// and every saturated colour are low, so a white glyph on light glass shows up as a pixel lighter than the background.
@Suite struct BatteryGlassTests {
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
        /// How far above the background a pixel may be on light glass: a system control lifts its own fill a little. Nil where
        /// the view draws light on a dark fill of its own on purpose.
        let wash: Double?
        /// Pixels of ink the view draws: at least this many are `reach` or more away from the background.
        let ink: Int
        var reach = 0.3
    }

    func state(percent: Int, charging: Bool = false) -> BatteryState {
        let state = BatteryState()
        state.snapshot = PowerSourceSnapshot(
            percent: percent, isCharging: charging, isOnAC: charging, minutesToEmpty: charging ? nil : 190, minutesToFull: charging ? 40 : nil
        )
        state.details = BatteryDetails(cycleCount: 312, healthPercent: 92, batteryWatts: 12, adapterWatts: 96)
        return state
    }

    func tab(percent: Int, charging: Bool = false) -> AnyView {
        AnyView(BatteryTabView(state: state(percent: percent, charging: charging), actions: BatteryTabActions(appeared: {}, disappeared: {})))
    }

    func lockScreen(percent: Int) -> AnyView {
        AnyView(ZStack { Color.black; BatteryLockScreenView(state: state(percent: percent)) })
    }

    var fixtures: [Fixture] {
        let size = CGSize(width: 452, height: BatteryGaugeLayout.height + BatteryTabView.factsGap + BatteryTabView.factsHeight)
        return [
            // The number sits inside the fill, light on a dark fill on light glass.
            Fixture(name: "number inside", view: tab(percent: 80), size: size, wash: nil, ink: 150),
            Fixture(name: "number beside", view: tab(percent: 12), size: size, wash: 0.005, ink: 150),
            Fixture(name: "charging", view: tab(percent: 45, charging: true), size: size, wash: 0.005, ink: 150),
            // The lock screen draws the widget on a black surface of its own, so its light text is meant to be on dark.
            Fixture(name: "lock screen", view: lockScreen(percent: 64), size: CGSize(width: 140, height: 40), wash: nil, ink: 100),
        ]
    }

    @Test func theNumberInsideThePlainFillIsLightOnLightGlassWhereTheFillIsDark() throws {
        let reading = try read(tab(percent: 80), glass: true, scheme: .light, size: CGSize(width: 452, height: 100))
        #expect(reading.lighter(than: 0.05) >= 100, "the number is light on the dark fill, not black on black")
    }

    @Test func theNumberInsideTheFillIsBlackOnTheColouredFillsAndOnTheClassicNotchAndTheInverseOfAPlainFillOnGlass() {
        for tone in [BatteryFillTone.charging, .lowPower, .low] {
            #expect(BatteryGauge.insideLabel(for: tone, onGlass: true) == Color.black)
            #expect(BatteryGauge.insideLabel(for: tone, onGlass: false) == Color.black)
        }
        #expect(BatteryGauge.insideLabel(for: .normal, onGlass: false) == Color.black)
        #expect(BatteryGauge.insideLabel(for: .normal, onGlass: true) == Color(nsColor: .windowBackgroundColor))
    }

    @Test func theLockScreenWidgetKeepsLightTextOnItsBlackSurfaceWhateverTheLookAndAppearanceAre() throws {
                for (glass, scheme) in [(true, ColorScheme.light), (true, .dark), (false, .light), (false, .dark)] {
            let reading = try read(lockScreen(percent: 64), glass: glass, scheme: scheme, size: CGSize(width: 140, height: 40))
            #expect(reading.pixels.filter { $0 > 0.5 }.count >= 100, "glass \(glass), \(scheme)")
        }
    }
    @Test func onLightGlassTheViewsDrawDarkAndNothingWhite() throws {
        for fixture in fixtures {
            let reading = try read(fixture.view, glass: true, scheme: .light, size: fixture.size)
            if let wash = fixture.wash {
                #expect(reading.lighter(than: wash) == 0, "\(fixture.name): something is drawn white on light glass")
            }
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
