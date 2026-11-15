#if DEBUG
import MyNotchCore
import MyNotchTestSupport
import SwiftUI
import Testing
@testable import NotchUI

/// Collects the debug log lines for the duration of one test body.
@MainActor
func captureNotchLog(_ body: () -> Void) -> [String] {
    var lines: [String] = []
    NotchLog.sink = { lines.append($0) }
    defer { NotchLog.sink = nil }
    body()
    return lines
}

@Suite struct NotchLogTests {
    let scheduler = ManualScheduler()

    func makeModel() -> NotchViewModel {
        NotchViewModel(scheduler: scheduler, availableTabs: { ["battery", "clipboard"] }, delays: { (.milliseconds(150), .milliseconds(300)) })
    }

    @Test func statesDescribeThemselvesWithModuleIdsOnly() {
        #expect(NotchState.closed.logDescription == "closed")
        #expect(NotchState.compact.logDescription == "compact")
        #expect(NotchState.toast.logDescription == "toast")
        #expect(NotchState.open("clipboard").logDescription == "open(clipboard)")
        #expect(NotchState.open(nil).logDescription == "open(-)")
    }

    @Test func everyLineStartsWithAMonotonicTimestamp() {
        let lines = captureNotchLog {
            NotchLog.record("first")
            NotchLog.record("second")
        }
        let stamps = lines.compactMap { line -> Double? in
            guard line.hasPrefix("t=") else { return nil }
            return Double(line.dropFirst(2).prefix { $0 != " " })
        }
        #expect(stamps.count == 2)
        #expect(stamps[0] <= stamps[1])
        #expect(lines[0].hasSuffix(" first"))
    }

    @Test func aTabSwitchLogsOneTransitionAndNeverACollapsedState() {
        let model = makeModel()
        model.open(tab: "battery")
        let lines = captureNotchLog {
            model.open(tab: "clipboard")
            model.open(tab: "battery")
        }
        let transitions = lines.filter { $0.contains(" state ") }
        #expect(transitions.count == 2)
        #expect(transitions[0].contains("open(battery) -> open(clipboard)"))
        #expect(transitions[1].contains("open(clipboard) -> open(battery)"))
        #expect(!lines.contains { $0.contains("-> closed") || $0.contains("-> compact") })
    }

    @Test func stateLinesCarryTheSelectedTabDragAndActivity() {
        let model = makeModel()
        model.hasActivity = true
        let lines = captureNotchLog {
            model.open(tab: "clipboard")
            model.setDragging(true)
            model.close()
        }
        #expect(lines.contains { $0.contains("closed -> open(clipboard)") && $0.contains("display=open(clipboard)") })
        #expect(lines.contains { $0.contains("dragging=true") })
        #expect(lines.contains { $0.contains("open(clipboard) -> closed") && $0.contains("display=compact") })
    }

    @Test func toastContentNeverReachesTheLog() {
        let model = makeModel()
        let lines = captureNotchLog {
            model.showToast(AnyView(Text("secret clipboard text")), duration: .seconds(2))
            scheduler.advance(by: .seconds(3))
        }
        #expect(!lines.isEmpty)
        #expect(!lines.contains { $0.contains("secret") })
    }
}
#endif
