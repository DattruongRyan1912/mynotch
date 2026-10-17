import SwiftUI
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

/// A live activity may draw across the top row of the collapsed notch (`LiveActivity.body`). Nothing else about an activity depends on
/// whether it does.
@Suite struct LiveActivityBodyTests {
    func make(id: String = "a", body: AnyView? = nil, bottom: AnyView? = nil, bottomHeight: CGFloat = 0) -> LiveActivity {
        LiveActivity(
            id: id, priority: .low, leading: AnyView(Color.clear), trailing: AnyView(Color.clear), bottom: bottom, bottomHeight: bottomHeight,
            body: body, minimal: AnyView(Color.red), summary: "một hoạt động"
        )
    }

    @Test func anActivityHasNoBodyUnlessItIsGivenOne() {
        let plain = LiveActivity(id: "a", leading: AnyView(Color.clear), trailing: AnyView(Color.clear))
        #expect(plain.body == nil && !plain.hasBody)
        let drawn = make(body: AnyView(Color.blue))
        #expect(drawn.body != nil && drawn.hasBody)
    }

    @Test func aBodyDoesNotGiveTheActivityAStripOrChangeAnythingElseAboutIt() {
        let plain = make()
        let drawn = make(body: AnyView(Color.blue))
        #expect(!drawn.hasBottom && drawn.bottomHeight == 0 && drawn.bottom == nil)
        #expect(drawn.id == plain.id && drawn.priority == plain.priority && drawn.summary == plain.summary)
        #expect(drawn.expiresAfter == plain.expiresAfter && (drawn.minimal != nil) == (plain.minimal != nil))
        // And it goes with a strip, which keeps its height.
        let both = make(body: AnyView(Color.blue), bottom: AnyView(Color.white), bottomHeight: 26)
        #expect(both.hasBody && both.hasBottom && both.bottomHeight == 26)
        // A strip with no view still has no height, body or not.
        #expect(make(body: AnyView(Color.blue), bottomHeight: 40).bottomHeight == 0)
    }

    @Test func theCenterKeepsTheBodyOfTheActivityItHoldsAndTheNewOneOfAnUpdate() {
        let center = ActivityCenter(scheduler: ManualScheduler())
        center.set(make(body: AnyView(Color.blue)), from: "pet")
        #expect(center.current?.activity.hasBody == true)
        center.set(make(), from: "pet")
        #expect(center.current?.activity.hasBody == false, "an update with no body has none")
        center.set(make(body: AnyView(Color.blue)), from: "pet")
        // An activity of a higher priority takes the notch and has none: the current one is the one that decides.
        center.set(
            LiveActivity(id: "t", priority: .high, leading: AnyView(Color.clear), trailing: AnyView(Color.clear)), from: "timer"
        )
        #expect(center.current?.activity.hasBody == false)
        #expect(center.others.first?.activity.hasBody == true)
        center.clear(id: "t", from: "timer")
        #expect(center.current?.activity.hasBody == true)
    }

    @Test func aStripIsForEveryScreenUnlessItIsForScreensWithAHardwareNotchOnly() {
        let everywhere = make(bottom: AnyView(Color.white), bottomHeight: 26)
        #expect(everywhere.bottomScope == .allScreens)
        #expect(everywhere.bottomHeight(onHardwareNotch: true) == 26 && everywhere.bottomHeight(onHardwareNotch: false) == 26)
        let hardware = LiveActivity(
            id: "a", leading: AnyView(Color.clear), trailing: AnyView(Color.clear), bottom: AnyView(Color.white), bottomHeight: 26,
            bottomScope: .hardwareNotchOnly, body: AnyView(Color.blue)
        )
        #expect(hardware.bottomScope == .hardwareNotchOnly && hardware.hasBottom && hardware.bottomHeight == 26)
        #expect(hardware.bottomHeight(onHardwareNotch: true) == 26)
        #expect(hardware.bottomHeight(onHardwareNotch: false) == 0, "a screen it is not for shows it with no strip")
        // No strip is no height on any screen.
        #expect(make().bottomHeight(onHardwareNotch: true) == 0 && make().bottomHeight(onHardwareNotch: false) == 0)
        #expect(LiveActivity(id: "a", leading: AnyView(Color.clear), trailing: AnyView(Color.clear)).bottomScope == .allScreens)
    }
}
