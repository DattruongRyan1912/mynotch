import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import CalendarModule

/// Colours no part of the tab draws with, so a pass can only mean that a view took the accent its environment gave it.
private let probeGreen = Color(.sRGB, red: 0, green: 1, blue: 0)
private let probeRed = Color(.sRGB, red: 1, green: 0, blue: 0)

/// The accent the user picked, in every mark of the Calendar tab. The environment is what the notch gives its content; a view that
/// asked for the notch's own purple instead would show it under any other accent.
@Suite struct CalendarAccentTests {
    let calendar = fixedCalendar()

    func actions() -> CalendarActions {
        CalendarActions(
            open: { _ in }, join: { _ in }, snooze: { _ in }, dismiss: { _ in }, complete: { _ in },
            requestRemindersAccess: {}, appeared: {}
        )
    }

    var onlineStandup: AgendaEvent {
        event("standup", calendar.on(14, at: 10), calendar.on(14, at: 11), meetingURL: URL(string: "https://whereby.com/acme-standup"))
    }

    /// The view as the notch shows it: over black, in the dark scheme.
    func bitmap<Content: View>(of view: Content, scale: CGFloat = 2) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark).background(Color.black))
        renderer.scale = scale
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    func count(in bitmap: NSBitmapImageRep, where isMatch: (NSColor) -> Bool) -> Int {
        var matches = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if let pixel = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), isMatch(pixel) { matches += 1 }
            }
        }
        return matches
    }

    /// Pixels whose colour is mostly green, as the probe accent draws them, however far text smoothing took them to black.
    func isGreenish(_ pixel: NSColor) -> Bool {
        pixel.greenComponent > 0.4 && pixel.greenComponent > 2 * pixel.redComponent && pixel.greenComponent > 2 * pixel.blueComponent
    }

    /// Pixels whose colour is mostly blue with some red: the notch's own purple, which nothing may draw under another accent.
    func isNotchPurple(_ pixel: NSColor) -> Bool {
        pixel.blueComponent > 0.4 && pixel.blueComponent > 1.5 * pixel.redComponent && pixel.blueComponent > 2 * pixel.greenComponent
    }

    // MARK: the join button

    @Test func theJoinButtonIsFilledWithTheEnvironmentsAccent() throws {
        let row = MeetingCardActions(event: onlineStandup, now: calendar.on(14, at: 9, 57), canSnooze: false, canDismiss: false, actions: actions())
        func capsule(under accent: Color) throws -> NSColor {
            let bitmap = try bitmap(of: row.environment(\.notchAccent, accent), scale: 1)
            // Inside the capsule's left end, before the label starts.
            return try #require(bitmap.colorAt(x: 6, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
        }
        let green = try capsule(under: probeGreen)
        #expect(green.greenComponent > 0.9 && green.redComponent < 0.1 && green.blueComponent < 0.1, "\(green)")
        let red = try capsule(under: probeRed)
        #expect(red.redComponent > 0.9 && red.greenComponent < 0.3 && red.blueComponent < 0.1, "\(red)")
    }

    @Test func theJoinLabelStaysReadableOnALightAccent() {
        let white = Color.white
        // The palette colours as macOS shows them on a dark surface (blue, purple, pink, red) keep the white they always had.
        for accent in [NotchAccent.Palette.blue, .purple, .pink, .red].map(\.rgb.color) {
            #expect(MeetingCardActions.labelColour(on: accent) == white)
        }
        // Yellow, orange and green are too light for white to be read on them.
        for accent in [NotchAccent.Palette.yellow, .orange, .green].map(\.rgb.color) {
            #expect(MeetingCardActions.labelColour(on: accent) != white)
        }
    }

    // MARK: the next event and the quick-add preview

    @Test func theNextEventsTimeIsDrawnInTheEnvironmentsAccent() throws {
        let state = CalendarState(now: calendar.on(14, at: 9, 57), calendar: calendar)
        state.featured = onlineStandup
        let card = UpcomingCard(state: state, actions: actions()).frame(width: CalendarTabView.cardWidth)
        let bitmap = try bitmap(of: card.environment(\.notchAccent, probeGreen))
        #expect(count(in: bitmap, where: isGreenish) > 20)
        #expect(count(in: bitmap, where: isNotchPurple) == 0, "nothing is left in the notch's own purple")
    }

    @Test func theQuickAddPreviewTimeIsDrawnInTheEnvironmentsAccent() throws {
        var quickAdd = QuickAddState(canWrite: true)
        quickAdd.text = "họp nhóm 3h chiều mai"
        quickAdd.draft = QuickAddDraft(title: "Họp nhóm", start: calendar.on(15, at: 15), end: calendar.on(15, at: 16), isAllDay: false, note: nil)
        let view = QuickAddView(quickAdd: quickAdd, now: calendar.on(14, at: 9, 57), calendar: calendar, actions: actions()).frame(width: 424, height: 120)
        let bitmap = try bitmap(of: view.environment(\.notchAccent, probeGreen))
        #expect(count(in: bitmap, where: isGreenish) > 20)
        #expect(count(in: bitmap, where: isNotchPurple) == 0, "nothing is left in the notch's own purple")
    }
}
