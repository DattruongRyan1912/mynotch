import AppKit
import Foundation
import NotchUI
import SwiftUI
import Testing
@testable import NotchUI
@testable import TodoModule

/// What the views draw on Liquid Glass, read from an offscreen render (glass itself cannot be drawn there, so the content is
/// drawn over a flat light or dark grey that stands in for it). Lightness is the least of red, green and blue: white is 1, black
/// and every saturated colour are low, so a white glyph on light glass shows up as a pixel lighter than the background.
@Suite struct TodoGlassTests {
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
        /// How far above the background a pixel may be on light glass: a system control lifts its own fill a little.
        let wash: Double
        /// Pixels of ink the view draws: at least this many are `reach` or more away from the background.
        let ink: Int
        var reach = 0.3
    }

    var fixtures: [Fixture] {
        let calendar = fixedCalendar()
        let now = calendar.on(14, at: 9, 57)
        func state(_ phase: TodoState.Phase) -> TodoState {
            let state = TodoState(now: now, calendar: calendar)
            state.phase = phase
            return state
        }
        let list = state(.ready)
        list.items = [
            TodoItem(reminder: todo("Nộp báo cáo", due: due(12), priority: .high), overdueDays: 2),
            TodoItem(reminder: todo("Họp nhóm", due: due(14, 9, 30), repeats: true), overdueDays: 0),
            TodoItem(reminder: todo("Mua sữa"), overdueDays: 0),
            TodoItem(reminder: todo("Gọi điện", done: now), overdueDays: 0),
        ]
        list.lingering = ["Gọi điện"]
        let hint = state(.needsAccess)
        let failed = state(.ready)
        failed.loadFailed = true
        failed.notice = "Không thêm được việc."
        let actions = TodoActions(
            complete: { _ in }, undo: { _ in }, add: { _ in true }, requestAccess: {}, retry: {}, watchAccess: {}, appeared: {}
        )
        let tab = CGSize(width: 452, height: 176)
        return [
            Fixture(name: "list", view: AnyView(TodoTabView(state: list, actions: actions)), size: tab, wash: 0.005, ink: 150),
            Fixture(name: "access hint", view: AnyView(TodoTabView(state: hint, actions: actions)), size: tab, wash: 0.005, ink: 150),
            Fixture(name: "failed read", view: AnyView(TodoTabView(state: failed, actions: actions)), size: tab, wash: 0.005, ink: 150),
            Fixture(name: "progress ring", view: AnyView(TodoProgressRing(fraction: 0.4)), size: CGSize(width: 28, height: 28), wash: 0.005, ink: 50, reach: 0.1),
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
