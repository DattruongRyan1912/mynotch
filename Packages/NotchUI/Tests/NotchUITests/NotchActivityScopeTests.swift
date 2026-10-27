import AppKit
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// An activity that is shown on some screens only: the notch of a screen takes, as its primary activity, the first one that is shown on
/// that screen, draws the bubbles and the list of what is shown on it, and is idle when nothing is.
@Suite struct NotchActivityScopeTests {
    let macBook = NotchGeometry(screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig())
    let external = NotchGeometry(screen: NotchGeometryTests.external, config: NotchLayoutConfig())
    let a = "A-0000"
    let b = "B-1111"

    func activity(
        _ id: String, _ scope: DisplayScope, _ priority: ActivityPriority = .normal, strip: Bool = false, bottomScope: BottomScope = .allScreens
    ) -> LiveActivity {
        LiveActivity(
            id: id, priority: priority, leading: AnyView(Color.clear), trailing: AnyView(Color.clear),
            bottom: strip ? AnyView(Color.white) : nil, bottomHeight: strip ? 26 : 0, bottomScope: bottomScope, displayScope: scope,
            body: strip ? AnyView(Color.clear) : nil
        )
    }

    func shown(_ slots: [ActivitySlot]) -> [String] {
        slots.map {
            switch $0 {
            case .activity(let entry): entry.id
            case .overflow(let count): "+\(count)"
            }
        }
    }

    // MARK: What a screen has

    @Test func theBubblesAndRowsOfAScreenLeaveOutWhatIsNotOnIt() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("pet", .only([a]), .high), from: "pet")
        center.set(activity("music", .allScreens, .normal), from: "media")
        center.set(activity("count", .allScreens, .low), from: "todo")
        let capacity = macBook.bubbleCapacity
        #expect(shown(ActivitySlot.bubbles(of: center.screen(a), capacity: capacity)) == ["media/music", "todo/count"])
        #expect(shown(ActivitySlot.bubbles(of: center.screen(b), capacity: capacity)) == ["todo/count"])
        #expect(shown(ActivitySlot.listRows(of: center.screen(a), capacity: 8)) == ["pet/pet", "media/music", "todo/count"])
        #expect(shown(ActivitySlot.listRows(of: center.screen(b), capacity: 8)) == ["media/music", "todo/count"])
        #expect(CompactAccessories.bubbleCount(activities: center.screen(a), geometry: macBook) == 2)
        #expect(CompactAccessories.bubbleCount(activities: center.screen(b), geometry: macBook) == 1)
        let open = CompactAccessories(activities: center.screen(b), geometry: macBook, isListOpen: true, state: .compact)
        #expect(open.bubbles == 1 && open.listRows == 2)
    }

    @Test func aScreenWithNothingShownOnItHasNoBubblesNoListAndNoStrip() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("pet", .only([a]), .low, strip: true), from: "pet")
        let screen = center.screen(b)
        let model = NotchViewModel(scheduler: ManualScheduler(), availableTabs: { [] }, delays: { (.zero, .zero) })
        model.reportStripWidth(300, for: "pet/pet")
        #expect(CompactAccessories(activities: screen, geometry: macBook, isListOpen: true, state: .compact) == .none)
        #expect(screen.stripHeight(on: .hardware) == 0 && !screen.currentHasBody)
        #expect(model.stripWidth(of: screen, on: .hardware) == 0, "it asks the notch of this screen for no width")
        #expect(model.stripWidth(of: center.screen(a), on: .hardware) == 300)
        #expect(center.screen(a).stripHeight(on: .hardware) == 26 && center.screen(a).currentHasBody)
    }

    @Test func theStripAndTheWidthAreThoseOfTheActivityThatIsPrimaryOnTheScreen() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("pet", .only([a]), .low, strip: true), from: "pet")
        center.set(activity("lyrics", .allScreens, .normal), from: "media")
        // The one that is on both is primary on both and has no strip.
        #expect(center.screen(a).stripHeight(on: .hardware) == 0 && center.screen(b).stripHeight(on: .hardware) == 0)
        center.clear(id: "lyrics", from: "media")
        #expect(center.screen(a).stripHeight(on: .hardware) == 26 && center.screen(b).stripHeight(on: .hardware) == 0)
    }

    @Test func theScreensStripScopeIsKeptOnTheScreensItIsShownOn() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("pet", .only([a]), .low, strip: true, bottomScope: .hardwareNotchOnly), from: "pet")
        #expect(center.screen(a).stripHeight(on: .hardware) == 26)
        #expect(center.screen(a).stripHeight(on: .virtual) == 0, "shown on this screen, with a strip for hardware notches only")
        #expect(center.screen(a).currentHasBody)
        #expect(center.screen(b).stripHeight(on: .hardware) == 0, "and not shown on the other whatever its kind")
        #expect(!center.screen(b).currentHasBody)
    }

    @Test func withNoDisplayScopeEveryScreenHasWhatItAlwaysHad() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(activity("pet", .allScreens, .low, strip: true), from: "pet")
        center.set(activity("music", .allScreens, .low), from: "media")
        let model = NotchViewModel(scheduler: ManualScheduler(), availableTabs: { [] }, delays: { (.zero, .zero) })
        model.reportStripWidth(300, for: "pet/pet")
        for feed in [center.screen(a), center.screen(b), center.screen(nil)] {
            #expect(feed.current?.id == "pet/pet" && feed.stripHeight(on: .hardware) == 26 && feed.stripHeight(on: .virtual) == 26)
            #expect(model.stripWidth(of: feed, on: .hardware) == 300)
            #expect(shown(ActivitySlot.bubbles(of: feed, capacity: 3)) == ["media/music"])
        }
        #expect(CompactAccessories(activities: center, geometry: macBook, isListOpen: false, state: .compact).bubbles == 1)
    }

    // MARK: What a screen draws

    func whites(_ geometry: NotchGeometry, display: String?, center: ActivityCenter, registry: RegistryHarness) throws -> Int {
        let model = NotchViewModel(scheduler: registry.scheduler, availableTabs: { [] }, delays: { (.zero, .zero) })
        model.hasActivity = true
        let root = NotchRootView(model: model, activities: center, registry: registry.registry, geometry: geometry, display: display)
            .frame(width: geometry.panelSize.width, height: geometry.panelSize.height)
        let renderer = ImageRenderer(content: root)
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        return (0..<bitmap.pixelsHigh).reduce(0) { total, y in
            total + (0..<bitmap.pixelsWide).filter { x in
                bitmap.colorAt(x: x, y: y).map { $0.redComponent > 0.9 && $0.greenComponent > 0.9 && $0.alphaComponent > 0.9 } ?? false
            }.count
        }
    }

    @Test func theNotchOfAScreenDrawsTheActivityOnlyIfItIsShownThere() throws {
        let harness = RegistryHarness([])
        harness.activities.set(activity("pet", .only([a]), .low, strip: true), from: "pet")
        #expect(try whites(macBook, display: a, center: harness.activities, registry: harness) > 1000, "the strip is under this notch")
        #expect(try whites(macBook, display: b, center: harness.activities, registry: harness) == 0, "and not under the other one")
        #expect(try whites(macBook, display: nil, center: harness.activities, registry: harness) > 1000, "no display: every activity")
    }

    @Test func theNotchOfAScreenDrawsTheNextActivityWhenTheFirstIsNotShownThere() throws {
        let harness = RegistryHarness([])
        harness.activities.set(activity("pet", .only([a]), .high), from: "pet")
        harness.activities.set(activity("lyrics", .allScreens, .normal, strip: true), from: "media")
        #expect(try whites(macBook, display: a, center: harness.activities, registry: harness) == 0, "the pet has no strip and is the primary")
        #expect(try whites(macBook, display: b, center: harness.activities, registry: harness) > 1000, "the next one is the primary here")
    }

    @Test func aStripThatIsForHardwareNotchesStillIsNotDrawnUnderAVirtualOneOnAScreenItIsShownOn() throws {
        let harness = RegistryHarness([])
        harness.activities.set(activity("pet", .only([a]), .low, strip: true, bottomScope: .hardwareNotchOnly), from: "pet")
        #expect(try whites(macBook, display: a, center: harness.activities, registry: harness) > 1000)
        #expect(try whites(external, display: a, center: harness.activities, registry: harness) == 0)
    }

    // MARK: What a screen's controller knows

    func controller(_ harness: RegistryHarness, on display: String?, id: CGDirectDisplayID) -> NotchWindowController {
        NotchWindowController(
            displayID: id, screen: NotchGeometryTests.macBook14, config: NotchLayoutConfig(), scheduler: harness.scheduler,
            registry: harness.registry, activities: harness.activities, delays: { (.milliseconds(150), .milliseconds(300)) },
            captureHiding: { .never }, swipesBetweenTabs: { true }, displayUUID: display
        )
    }

    func settle(until condition: () -> Bool) async {
        for _ in 0..<500 where !condition() { await Task.yield() }
    }

    @Test func theNotchOfAScreenIsIdleWhenTheOnlyActivityIsNotShownOnIt() async {
        let harness = RegistryHarness([])
        harness.activities.set(activity("pet", .only([a]), .low), from: "pet")
        let first = controller(harness, on: a, id: 1)
        defer { first.close() }
        let second = controller(harness, on: b, id: 2)
        defer { second.close() }
        await settle { first.model.hasActivity }
        // The other notch has looked at the activities by now as well (the next test shows that it does follow them).
        for _ in 0..<100 { await Task.yield() }
        #expect(first.model.hasActivity && first.model.displayState == .compact)
        #expect(!second.model.hasActivity && second.model.displayState == .closed, "the notch there is plain, as if there was no pet")
    }

    @Test func anActivityEveryScreenShowsReachesTheOtherScreenAndLeavesIt() async {
        let harness = RegistryHarness([])
        harness.activities.set(activity("pet", .only([a]), .low), from: "pet")
        let first = controller(harness, on: a, id: 1)
        defer { first.close() }
        let second = controller(harness, on: b, id: 2)
        defer { second.close() }
        await settle { first.model.hasActivity }
        harness.activities.set(activity("music", .allScreens, .normal), from: "media")
        await settle { second.model.hasActivity }
        #expect(first.model.hasActivity && second.model.hasActivity)
        harness.activities.clear(id: "music", from: "media")
        await settle { !second.model.hasActivity }
        #expect(first.model.hasActivity && !second.model.hasActivity)
        harness.activities.clear(id: "pet", from: "pet")
        await settle { !first.model.hasActivity }
        #expect(!first.model.hasActivity && !second.model.hasActivity)
    }

    @Test func theScopeOfAnActivityThatIsSetAgainMovesItToTheOtherScreen() async {
        let harness = RegistryHarness([])
        harness.activities.set(activity("pet", .only([a]), .low), from: "pet")
        let first = controller(harness, on: a, id: 1)
        defer { first.close() }
        let second = controller(harness, on: b, id: 2)
        defer { second.close() }
        await settle { first.model.hasActivity }
        harness.activities.set(activity("pet", .only([b]), .low), from: "pet")
        await settle { second.model.hasActivity && !first.model.hasActivity }
        #expect(!first.model.hasActivity && second.model.hasActivity)
    }

    @Test func aControllerWithNoDisplayHasEveryActivityAsItAlwaysDid() async {
        let harness = RegistryHarness([])
        harness.activities.set(activity("pet", .only([a]), .low), from: "pet")
        let unknown = controller(harness, on: nil, id: 3)
        defer { unknown.close() }
        await settle { unknown.model.hasActivity }
        #expect(unknown.model.hasActivity)
    }
}
