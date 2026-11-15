import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

@Suite struct NotchPresenceTests {
    @Test func aWindowCountsAsOnScreenOnlyWhenOrderedInAndNotEntirelyHidden() {
        #expect(NotchPresence.isOnScreen(isVisible: true, occlusion: [.visible]))
        #expect(!NotchPresence.isOnScreen(isVisible: true, occlusion: []))
        #expect(!NotchPresence.isOnScreen(isVisible: false, occlusion: [.visible]))
        #expect(!NotchPresence.isOnScreen(isVisible: false, occlusion: []))
    }

    @Test func viewsOutsideANotchAreOnScreen() {
        #expect(EnvironmentValues().notchIsOnScreen)
        #expect(NotchViewModel(scheduler: ManualScheduler(), availableTabs: { [] }, delays: { (.zero, .zero) }).isOnScreen)
    }

    /// Records what the environment says when SwiftUI evaluates it.
    struct Probe: View {
        @Environment(\.notchIsOnScreen) private var isOnScreen
        let record: (Bool) -> Void

        var body: some View {
            let _ = record(isOnScreen)
            Color.clear
        }
    }

    @Test(arguments: [true, false]) func theRootViewHandsTheModelsStateToEveryViewInIt(isOnScreen: Bool) {
        let harness = RegistryHarness([])
        let model = NotchViewModel(scheduler: harness.scheduler, availableTabs: { [] }, delays: { (.milliseconds(150), .milliseconds(300)) })
        model.hasActivity = true
        model.isOnScreen = isOnScreen
        var seen: [Bool] = []
        harness.activities.set(
            LiveActivity(id: "probe", leading: AnyView(Probe { seen.append($0) }), trailing: AnyView(Color.clear), summary: "probe"), from: "m"
        )
        let geometry = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
        let root = NotchRootView(model: model, activities: harness.activities, registry: harness.registry, geometry: geometry)
        _ = ImageRenderer(content: root).cgImage
        #expect(!seen.isEmpty)
        #expect(seen.allSatisfy { $0 == isOnScreen })
    }
}

/// A timeline hosted in a window that is never shown; the run loop ticks it like it would any other.
@Suite struct NotchTimelineTests {
    func evaluations(isOnScreen: Bool, for seconds: TimeInterval) -> Int {
        var count = 0
        let timeline = NotchTimeline(every: 0.03) { _ in
            let _ = count += 1
            Color.clear
        }
        .environment(\.notchIsOnScreen, isOnScreen)
        let hosting = NSHostingView(rootView: timeline)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 50, height: 50), styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        window.contentView = nil
        return count
    }

    @Test func tickingWhileOnScreen() {
        #expect(evaluations(isOnScreen: true, for: 0.2) >= 3)
    }

    @Test func standingStillWhileOffScreen() {
        #expect(evaluations(isOnScreen: false, for: 0.2) == 1)
    }
}
