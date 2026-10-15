import AppKit
import Foundation
import NotchUI
import SwiftUI
import Testing
@testable import NotchUI
@testable import CalendarModule

/// What the views draw on Liquid Glass, read from an offscreen render (glass itself cannot be drawn there, so the content is
/// drawn over a flat light or dark grey that stands in for it). Lightness is the least of red, green and blue: white is 1, black
/// and every saturated colour are low, so a white glyph on light glass shows up as a pixel lighter than the background.
@Suite struct CalendarGlassTests {
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

    let calendar = fixedCalendar()

    var actions: CalendarActions {
        CalendarActions(
            open: { _ in }, join: { _ in }, snooze: { _ in }, dismiss: { _ in }, complete: { _ in },
            requestRemindersAccess: {}, appeared: {}
        )
    }

    @Test func theJoinLabelIsWhiteOnTheAccentOnLightGlassToo() throws {
        let online = event("họp", calendar.on(14, at: 10), calendar.on(14, at: 11), meetingURL: URL(string: "https://whereby.com/acme"))
        let join = MeetingCardActions(event: online, now: calendar.on(14, at: 9, 57), canSnooze: false, canDismiss: false, actions: actions)
        let reading = try read(join, glass: true, scheme: .light, size: CGSize(width: 100, height: 30))
        #expect(reading.lighter(than: 0.05) >= 50, "a white label on the accent, not a black one")
    }

    var fixtures: [Fixture] {
        let calendar = calendar
        let actions = actions
        func state() -> CalendarState {
            let state = CalendarState(now: calendar.on(14, at: 9, 57), calendar: calendar)
            state.daySummary = "Hôm nay: 3 sự kiện, rảnh 14:00–16:00"
            return state
        }
        // The card's "Tham gia" is white on the accent on purpose, so it has a fixture of its own.
        let meeting = event("họp", calendar.on(14, at: 10), calendar.on(14, at: 11), title: "Họp kế hoạch quý", location: "Phòng 4B")
        let online = event("họp", calendar.on(14, at: 10), calendar.on(14, at: 11), meetingURL: URL(string: "https://whereby.com/acme"))
        let busy = state()
        busy.featured = meeting
        busy.canDismissFeatured = true
        busy.canSnoozeFeatured = true
        busy.agenda = Agenda(today: [meeting, event("trưa", calendar.on(14, at: 12), calendar.on(14, at: 13), title: "Ăn trưa với Lan")], next: meeting, upcoming: [meeting])
        busy.reminders = .items([reminder("Nộp báo cáo", due: DateComponents(year: 2026, month: 10, day: 14, hour: 17)), reminder("Mua sữa", due: DateComponents(year: 2026, month: 10, day: 13), overdue: true)])
        let access = state()
        access.reminders = .needsAccess
        let adding = state()
        var quickAdd = QuickAddState(canWrite: true)
        quickAdd.text = "họp nhóm 3h chiều mai"
        quickAdd.draft = QuickAddDraft(title: "Họp nhóm", start: calendar.on(15, at: 15), end: calendar.on(15, at: 16), isAllDay: false, note: nil)
        quickAdd.calendar = CalendarInfo(id: "work", title: "Công việc", color: .gray)
        adding.quickAdd = quickAdd
        let tab = CGSize(width: 452, height: 176)
        return [
            Fixture(name: "day", view: AnyView(CalendarTabView(state: busy, actions: actions)), size: tab, wash: 0.005, ink: 150, reach: 0.15),
            Fixture(name: "reminders access", view: AnyView(CalendarTabView(state: access, actions: actions)), size: tab, wash: 0.005, ink: 150, reach: 0.15),
            Fixture(name: "quick add", view: AnyView(CalendarTabView(state: adding, actions: actions)), size: tab, wash: 0.005, ink: 150, reach: 0.15),
            Fixture(name: "join", view: AnyView(MeetingCardActions(event: online, now: calendar.on(14, at: 9, 57), canSnooze: true, canDismiss: true, actions: actions)), size: CGSize(width: 230, height: 30), wash: nil, ink: 100, reach: 0.15),
            Fixture(name: "add button", view: AnyView(AddEventButton(isOpen: false, actions: actions)), size: CGSize(width: 30, height: 30), wash: 0.005, ink: 10),
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
