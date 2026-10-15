import AppKit
import AgentHookKit
import Foundation
import MyNotchTestSupport
import NotchUI
import SwiftUI
import Testing
@testable import NotchUI
@testable import AIAgentsModule

/// What the views draw on Liquid Glass, read from an offscreen render (glass itself cannot be drawn there, so the content is
/// drawn over a flat light or dark grey that stands in for it). Lightness is the least of red, green and blue: white is 1, black
/// and every saturated colour are low, so a white glyph on light glass shows up as a pixel lighter than the background.
@Suite struct AIAgentsGlassTests {
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

    var fixtures: [Fixture] {
        let scheduler = ManualScheduler()
        let queue = PermissionQueue(scheduler: scheduler)
        queue.add(
            HookPayload(
                source: "claude", event: "PermissionRequest", sessionID: "s0", cwd: "/p", tool: "Bash", timestamp: Date(timeIntervalSince1970: 1_800_000_000),
                detail: PermissionDetail(text: "rm -rf build", hiddenLines: 0, isComplete: true)
            )
        ) { _ in }
        scheduler.advance(by: PermissionQueue.armingDelay)
        let store = AgentSessionStore(scheduler: scheduler)
        store.apply((1...3).map { AgentEvent(source: .claude, sessionID: "session-\($0)", timestamp: nil, kind: .turnStarted) })
        let hint = AgentJumpHint()
        hint.message = AgentJumpHint.automationDenied
        let actions = AgentTabActions(jump: { _ in false }, openFolder: { _ in }, copyPath: { _ in }, decide: { _, _ in })
        let tab = CGSize(width: 452, height: 200)
        return [
            Fixture(name: "sessions", view: AnyView(AIAgentsTabView(store: store, permissions: PermissionQueue(scheduler: scheduler), actions: actions)), size: tab, wash: 0.005, ink: 150, reach: 0.15),
            Fixture(name: "request and hint", view: AnyView(AIAgentsTabView(store: store, permissions: queue, actions: actions, hint: hint)), size: tab, wash: 0.005, ink: 150, reach: 0.15),
            Fixture(
                name: "usage footer",
                view: AnyView(AgentUsageFooter(
                    usage: [AgentTabState.UsageLine(source: .claude, tokens: "1,2 triệu", cost: "$3,40", isEstimated: true)],
                    limits: [AgentTabState.LimitBar(id: "5h", label: "5 giờ", percent: 40, resets: nil)]
                )),
                size: CGSize(width: 452, height: 60), wash: 0.005, ink: 100, reach: 0.15
            ),
        ]
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
            for scheme in fixture.classicSchemes {
                let reading = try read(fixture.view, glass: false, scheme: scheme, size: fixture.size)
                #expect(reading.lighter(than: fixture.reach) >= fixture.ink, "\(fixture.name) in \(scheme)")
            }
        }
    }
}
