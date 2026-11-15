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
        /// The appearances the classic notch is checked in: a view that draws with the system's colours has only the dark one.
        var classicSchemes: [ColorScheme] = [.dark, .light]
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
        list.viewMode = .list

        let matrix = state(.ready)
        matrix.items = list.items
        matrix.lingering = list.lingering
        matrix.viewMode = .matrix

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
            Fixture(name: "matrix", view: AnyView(TodoTabView(state: matrix, actions: actions)), size: tab, wash: 0.005, ink: 150),
            Fixture(name: "quick add field", view: AnyView(TodoQuickAddField(state: list, actions: actions).notchColorScheme()), size: CGSize(width: 452, height: 32), wash: 0.005, ink: 80, reach: 0.15),
            Fixture(name: "access hint", view: AnyView(TodoTabView(state: hint, actions: actions)), size: tab, wash: 0.005, ink: 150),
            Fixture(name: "failed read", view: AnyView(TodoTabView(state: failed, actions: actions)), size: tab, wash: 0.005, ink: 150),
            Fixture(name: "progress ring", view: AnyView(TodoProgressRing(fraction: 0.4)), size: CGSize(width: 28, height: 28), wash: 0.005, ink: 50, reach: 0.1),
        ]
    }

    @Test func quickAddFieldPinsNotchOnlyWhileNonEmptyTextIsFocused() {
        #expect(!TodoQuickAddField.pinsNotch(text: "", isFocused: false))
        #expect(!TodoQuickAddField.pinsNotch(text: "", isFocused: true))
        #expect(!TodoQuickAddField.pinsNotch(text: "gọi khách", isFocused: false))
        #expect(TodoQuickAddField.pinsNotch(text: "gọi khách", isFocused: true))
    }

    @MainActor
    @Test("Render Todo Liquid Glass Visual Evidence")
    func renderVisualEvidence() throws {
        let calendar = fixedCalendar()
        let now = calendar.on(14, at: 9, 57)
        let state = TodoState(now: now, calendar: calendar)
        state.phase = .ready
        state.items = [
            TodoItem(reminder: todo("Nộp báo cáo quý 4 (!q1 gấp)", due: due(12), priority: .high), overdueDays: 2),
            TodoItem(reminder: todo("Họp sprint chiến lược (#q2)", due: due(14, 9, 30), repeats: true), overdueDays: 0),
            TodoItem(reminder: todo("Gửi email đối tác (!q3)", due: due(14, 15, 0)), overdueDays: 0),
            TodoItem(reminder: todo("Mua sữa & dọn dẹp (#q4)"), overdueDays: 0),
            TodoItem(reminder: todo("Gọi điện khách hàng", done: now), overdueDays: 0),
        ]
        state.lingering = ["Gọi điện khách hàng"]
        state.viewMode = .matrix

        let actions = TodoActions(
            complete: { _ in }, undo: { _ in }, add: { _ in true }, requestAccess: {}, retry: {}, watchAccess: {}, appeared: {}
        )

        let matrixContent = TodoTabView(state: state, actions: actions)
            .padding(14)
            .frame(width: 520, height: 260)
            .background(Color(red: 20/255, green: 20/255, blue: 23/255).opacity(0.85))
            .environment(\.colorScheme, .dark)
            .environment(\.notchSurface, .liquidGlass(tinted: false))
            .environment(\.notchAccent, Color(red: 14/255, green: 165/255, blue: 233/255))

        let hosting = NSHostingView(rootView: matrixContent)
        hosting.frame = NSRect(x: 0, y: 0, width: 520, height: 260)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let pngData = rep.representation(using: .png, properties: [:]) else { return }

        let outURL1 = URL(fileURLWithPath: "/Users/ryantruong/Project/MyNotch/docs/evidence/todo_liquid_glass_evidence.png")
        let outURL2 = URL(fileURLWithPath: "/Users/ryantruong/.gemini/antigravity-cli/brain/ee26def0-ef76-4a07-abf4-8e638469f7ed/todo_liquid_glass_evidence.png")

        try? FileManager.default.createDirectory(at: outURL1.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? pngData.write(to: outURL1)
        try? pngData.write(to: outURL2)
        #expect(pngData.count > 1000)
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
