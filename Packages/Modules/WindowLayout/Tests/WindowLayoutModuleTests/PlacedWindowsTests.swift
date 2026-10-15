import CoreGraphics
import Testing
@testable import WindowLayoutModule

/// The windows MyNotch put into a zone, as the next placement sees them: only those still where they were put. Fake
/// windows only.
@Suite struct PlacedWindowsTests {
    let registry = PlacedWindows()
    let left = SnapTarget(layout: .leftHalf, zone: 0)
    let right = SnapTarget(layout: .rightHalf, zone: 0)
    let leftFrame = CGRect(x: 0, y: 37, width: 1040, height: 945)

    func window(_ bundleID: String, at frame: CGRect) -> FakeWindow {
        FakeWindow(frame: frame, app: SnapApp(bundleID: bundleID, name: bundleID))
    }

    @Test func aPlacedWindowIsReportedWithItsAppZoneAndFrame() {
        let first = window("com.example.first", at: leftFrame)
        registry.record(first, in: left, frame: leftFrame)
        let found = registry.current(excluding: FakeWindow())
        #expect(found.count == 1)
        #expect(found.first?.app.bundleID == "com.example.first")
        #expect(found.first?.target == left)
        #expect(found.first?.frame == leftFrame)
    }

    @Test func theWindowAskedAboutIsNotItsOwnNeighbour() {
        let first = window("com.example.first", at: leftFrame)
        let second = window("com.example.second", at: CGRect(x: 1040, y: 37, width: 472, height: 945))
        registry.record(first, in: left, frame: leftFrame)
        registry.record(second, in: right, frame: second.current!)
        #expect(registry.current(excluding: first).map(\.target) == [right])
        #expect(registry.current(excluding: second).map(\.target) == [left])
    }

    @Test func recordingTheSameWindowAgainReplacesItsOldPlace() {
        let first = window("com.example.first", at: leftFrame)
        registry.record(first, in: left, frame: leftFrame)
        let moved = CGRect(x: 472, y: 37, width: 1040, height: 945)
        first.current = moved
        registry.record(first, in: right, frame: moved)
        #expect(registry.count == 1)
        #expect(registry.current(excluding: FakeWindow()).map(\.target) == [right])
    }

    @Test func aWindowThatWasClosedIsForgotten() {
        let first = window("com.example.first", at: leftFrame)
        registry.record(first, in: left, frame: leftFrame)
        first.close()
        #expect(registry.current(excluding: FakeWindow()).isEmpty)
        #expect(registry.count == 0, "forgotten, not only skipped")
    }

    @Test func aWindowTheUserMovedAwayIsForgotten() {
        let first = window("com.example.first", at: leftFrame)
        registry.record(first, in: left, frame: leftFrame)
        first.drag(to: CGPoint(x: 300, y: 200))
        #expect(registry.current(excluding: FakeWindow()).isEmpty)
        #expect(registry.count == 0)
    }

    @Test func aWindowTheUserResizedIsForgotten() {
        let first = window("com.example.first", at: leftFrame)
        registry.record(first, in: left, frame: leftFrame)
        first.current = CGRect(x: 0, y: 37, width: 900, height: 945)
        #expect(registry.current(excluding: FakeWindow()).isEmpty)
    }

    @Test func aDriftOfTwoPointsIsStillThereAndTheLiveFrameIsTheOneReported() {
        let first = window("com.example.first", at: leftFrame)
        registry.record(first, in: left, frame: leftFrame)
        let drifted = CGRect(x: 1, y: 38, width: 1042, height: 944)
        first.current = drifted
        #expect(registry.current(excluding: FakeWindow()).first?.frame == drifted)
        first.current = CGRect(x: 0, y: 37, width: 1043.5, height: 945)
        #expect(registry.current(excluding: FakeWindow()).isEmpty, "more than two points is the user's doing")
    }

    @Test func onlyTheNewestWindowsAreKept() {
        let windows = (0..<(PlacedWindows.capacity + 2)).map { index in
            window("com.example.w\(index)", at: CGRect(x: CGFloat(index) * 10, y: 37, width: 100, height: 100))
        }
        for window in windows { registry.record(window, in: left, frame: window.current!) }
        #expect(registry.count == PlacedWindows.capacity)
        let kept = registry.current(excluding: FakeWindow()).compactMap(\.app.bundleID)
        #expect(kept == windows.suffix(PlacedWindows.capacity).compactMap(\.app.bundleID))
    }

    @Test func clearingForgetsEverything() {
        registry.record(window("com.example.first", at: leftFrame), in: left, frame: leftFrame)
        registry.removeAll()
        #expect(registry.count == 0)
        #expect(registry.current(excluding: FakeWindow()).isEmpty)
    }
}
