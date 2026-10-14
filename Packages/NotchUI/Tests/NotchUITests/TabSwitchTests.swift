#if DEBUG
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// A tab switch must be one `open(a) -> open(b)` step: the shape stays mounted and only its height animates.
@Suite struct TabSwitchTests {
    let scheduler = ManualScheduler()
    let tabs: [ModuleID] = ["battery", "clipboard", "media"]

    func makeModel(_ tabs: @escaping () -> [ModuleID]) -> NotchViewModel {
        NotchViewModel(scheduler: scheduler, availableTabs: tabs, delays: { (.milliseconds(150), .milliseconds(300)) })
    }

    /// The `from -> to` pair of every state change in `lines`.
    func states(_ lines: [String]) -> [(from: String, to: String)] {
        lines.compactMap { line in
            guard let range = line.range(of: " state "), let arrow = line.range(of: " -> ", range: range.upperBound..<line.endIndex) else { return nil }
            let from = String(line[range.upperBound..<arrow.lowerBound])
            let to = String(line[arrow.upperBound...].prefix { $0 != " " })
            return (from, to)
        }
    }

    @Test func clickingTabsInTheBarGoesStraightFromTabToTab() {
        let model = makeModel { tabs }
        model.pointerEntered()
        scheduler.advance(by: .milliseconds(150))
        let lines = captureNotchLog {
            model.open(tab: "clipboard")
            model.open(tab: "media")
            model.open(tab: "battery")
        }
        let steps = states(lines)
        #expect(steps.map(\.from) == ["open(battery)", "open(clipboard)", "open(media)"])
        #expect(steps.map(\.to) == ["open(clipboard)", "open(media)", "open(battery)"])
        #expect(model.lastTab == "battery")
    }

    @Test func reselectingTheShownTabChangesNothing() {
        let model = makeModel { tabs }
        model.open(tab: "media")
        let lines = captureNotchLog { model.open(tab: "media") }
        #expect(states(lines).isEmpty)
        #expect(model.state == .open("media"))
    }

    @Test func aToastEndingReturnsToTheTabWithoutCollapsing() {
        let model = makeModel { tabs }
        model.open(tab: "clipboard")
        let lines = captureNotchLog {
            model.showToast(AnyView(EmptyView()), duration: .seconds(2))
            scheduler.advance(by: .seconds(2))
        }
        let steps = states(lines)
        #expect(steps.map(\.to) == ["toast", "open(clipboard)"])
        #expect(model.tabUnderToast == nil)
    }

    @Test func aDragSwitchesTheOpenTabWithoutCollapsing() {
        let model = makeModel { tabs }
        model.open(tab: "battery")
        let lines = captureNotchLog {
            model.dragEntered(tab: "clipboard")
            model.dragExited()
        }
        #expect(states(lines).map(\.to) == ["open(clipboard)"])
        #expect(model.state == .open("clipboard"))
    }

    @Test func aTabWhoseModuleStoppedFallsBackToAnotherTabNotToClosed() {
        var available: [ModuleID] = ["battery", "clipboard"]
        let model = makeModel { available }
        model.open(tab: "clipboard")
        available = ["battery"]
        let lines = captureNotchLog { model.open(tab: "clipboard") }
        #expect(states(lines).map(\.to) == ["open(battery)"])
    }

    @Test func switchingWhileAnActivityShowsNeverPassesThroughCompact() {
        let model = makeModel { tabs }
        model.hasActivity = true
        model.open(tab: "battery")
        let lines = captureNotchLog {
            model.open(tab: "media")
            model.open(tab: "clipboard")
        }
        #expect(states(lines).allSatisfy { !$0.to.hasPrefix("closed") && !$0.to.hasPrefix("compact") })
        #expect(model.displayState == .open("clipboard"))
    }
}
#endif
