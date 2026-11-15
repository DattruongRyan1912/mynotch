import CoreGraphics
import Testing
@testable import ScreenshotModule

@Suite struct TimelineGeometryTests {
    let geometry = TimelineGeometry(width: 600, duration: 60)

    @Test func timeAndPositionAreEachOthersInverse() {
        #expect(geometry.x(for: 0) == 0 && geometry.x(for: 30) == 300 && geometry.x(for: 60) == 600)
        for time in stride(from: 0.0, through: 60, by: 7.3) {
            #expect(abs(geometry.time(at: geometry.x(for: time)) - time) < 1e-9)
        }
    }

    @Test func anythingOutsideIsKeptInside() {
        #expect(geometry.x(for: -5) == 0 && geometry.x(for: 90) == 600)
        #expect(geometry.time(at: -10) == 0 && geometry.time(at: 700) == 60)
        #expect(geometry.x(for: .nan) == 0 && geometry.time(at: .nan) == 0)
    }

    @Test func anEmptyTimelineAnswersWithZerosAndNoMarks() {
        let none = TimelineGeometry(width: 0, duration: 0)
        #expect(none.x(for: 3) == 0 && none.time(at: 3) == 0)
        #expect(none.rulerTicks().isEmpty)
        #expect(TimelineGeometry(width: 500, duration: 0).rulerTicks().isEmpty)
    }

    @Test func aRangeIsAPositionAndAWidth() {
        let span = geometry.span(of: 10..<25)
        #expect(span.x == 100 && span.width == 150)
        let past = geometry.span(of: 50..<80)
        #expect(past.x == 500 && past.width == 100)
    }

    @Test func theRulerMarksRoundSecondsWithRoomBetweenThem() {
        let ticks = geometry.rulerTicks(minimumSpacing: 64)
        // 10 points a second: the first step that is 64 points wide or more is 10 s.
        #expect(ticks.map(\.time) == [0, 10, 20, 30, 40, 50, 60])
        #expect(ticks.map(\.label) == ["0:00", "0:10", "0:20", "0:30", "0:40", "0:50", "1:00"])
        let narrow = TimelineGeometry(width: 100, duration: 3_600).rulerTicks(minimumSpacing: 64)
        #expect(narrow.count >= 2)
        for (a, b) in zip(narrow, narrow.dropFirst()) { #expect(TimelineGeometry(width: 100, duration: 3_600).x(for: b.time - a.time) >= 64) }
    }

    @Test func timesAreWrittenAsMinutesAndSeconds() {
        #expect(TimelineGeometry.label(for: 0) == "0:00")
        #expect(TimelineGeometry.label(for: 5.9) == "0:05")
        #expect(TimelineGeometry.label(for: 75) == "1:15")
        #expect(TimelineGeometry.label(for: 3_723) == "1:02:03")
        #expect(TimelineGeometry.label(for: -4) == "0:00")
    }
}
