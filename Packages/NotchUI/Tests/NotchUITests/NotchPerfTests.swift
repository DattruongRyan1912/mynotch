#if DEBUG
import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

@Suite struct NotchPerfTests {
    /// Reports whatever was counted before, so a test starts from zero.
    func resetCounters() {
        NotchPerf.report(over: .seconds(1))
    }

    func report(over elapsed: Duration) -> String {
        var line = ""
        NotchPerf.sink = { line = $0 }
        defer { NotchPerf.sink = nil }
        NotchPerf.report(over: elapsed)
        return line
    }

    @Test func theReportGivesEveryCounterAsARatePerSecond() {
        resetCounters()
        for _ in 0..<5 { NotchPerf.count(.layouts) }
        for _ in 0..<3 { NotchPerf.count(.spectrumUpdates) }
        #expect(report(over: .seconds(10)) == "layouts/s=0.5, bodies/s=0.0, spectrumUpdates/s=0.3")
    }

    @Test func aReportStartsTheNextOneFromZero() {
        resetCounters()
        for _ in 0..<20 { NotchPerf.count(.bodies) }
        #expect(report(over: .seconds(10)) == "layouts/s=0.0, bodies/s=2.0, spectrumUpdates/s=0.0")
        #expect(report(over: .seconds(10)) == "layouts/s=0.0, bodies/s=0.0, spectrumUpdates/s=0.0")
    }

    @Test func theReportIsTenSecondsApart() {
        #expect(NotchPerf.reportInterval == .seconds(10))
    }

    @Test func everyLayoutPassOfTheHostingViewIsCounted() {
        let hosting = FirstMouseHostingView(rootView: Text("notch"))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 100), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        resetCounters()
        hosting.needsLayout = true
        hosting.layoutSubtreeIfNeeded()
        let first = NotchPerf.counted(.layouts)
        #expect(first >= 1)
        hosting.needsLayout = true
        hosting.layoutSubtreeIfNeeded()
        #expect(NotchPerf.counted(.layouts) > first)
        // Nothing invalidated, nothing laid out.
        let settled = NotchPerf.counted(.layouts)
        hosting.layoutSubtreeIfNeeded()
        #expect(NotchPerf.counted(.layouts) == settled)
    }

    @Test func everyEvaluationOfTheRootBodyIsCounted() throws {
        let harness = RegistryHarness([])
        let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { [] }, delays: { (.milliseconds(150), .milliseconds(300)) })
        let geometry = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
        let root = NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: geometry)
        resetCounters()
        let renderer = ImageRenderer(content: root)
        _ = renderer.cgImage
        #expect(NotchPerf.counted(.bodies) >= 1)
    }
}
#endif
