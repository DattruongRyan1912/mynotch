import AppKit
import SwiftUI
import Testing
@testable import PerformanceModule

/// The button of the helper's line is the one thing that must never be cut off: the line sits in half of a notch (216 pt at the
/// narrowest, and the memory column can take more than its half), and with Macs Fan Control running it has a warning too.
@Suite struct FanHelperRowLayoutTests {
    /// The row hosted at `width`, laid out, with where it put its parts.
    func frames(of helper: FanHelperManager, width: CGFloat) async -> [FanHelperRow.Part: CGRect] {
        nonisolated(unsafe) var seen: [FanHelperRow.Part: CGRect] = [:]
        let host = NSHostingView(rootView: FanHelperRow(helper: helper, report: { seen = $0 }).frame(width: width))
        host.frame = CGRect(x: 0, y: 0, width: width, height: FanHelperRow.height)
        host.layoutSubtreeIfNeeded()
        for _ in 0..<50 where seen.isEmpty {
            try? await Task.sleep(for: .milliseconds(10))
            host.layoutSubtreeIfNeeded()
        }
        return seen
    }

    /// What a button of this label measures when nothing limits it.
    func idealSize(of title: String) -> CGSize {
        NSHostingView(rootView: FanHelperButton(title: title, action: {}).fixedSize()).fittingSize
    }

    static let rigs: [(name: String, action: FanHelperAction?, rig: @MainActor () -> HelperRig)] = [
        ("not installed, Macs Fan Control running", .install, { HelperRig(status: .notRegistered, runningApps: [FanHelperManager.macsFanControlBundleID]) }),
        ("not installed", .install, { HelperRig(status: .notRegistered) }),
        ("needs approval, Macs Fan Control running", .openSettings, { HelperRig(status: .requiresApproval, runningApps: [FanHelperManager.macsFanControlBundleID]) }),
        ("unreachable, Macs Fan Control running", .retry, { HelperRig(status: .enabled, pings: [.failure(.timeout)], runningApps: [FanHelperManager.macsFanControlBundleID]) }),
    ]

    @Test func theButtonIsWholeAndInsideTheRowAtHalfTheNarrowestNotchAndBelow() async {
        for (name, action, make) in Self.rigs {
            let rig = make()
            await rig.manager.refresh()
            let ideal = idealSize(of: action!.compactTitle)
            for width in [CGFloat(216), 200, 180, 160, 140] {
                let parts = await frames(of: rig.manager, width: width)
                guard let button = parts[.button] else {
                    Issue.record("\(name) at \(width): no button")
                    continue
                }
                #expect(button.minX >= 0 && button.maxX <= width + 0.5, "\(name) at \(width): button \(button) is outside the row")
                #expect(button.width >= ideal.width - 0.5, "\(name) at \(width): button is \(button.width) wide, \(ideal.width) wanted")
                #expect(button.height >= ideal.height - 0.5 && button.minY >= -0.5 && button.maxY <= FanHelperRow.height + 0.5, "\(name) at \(width): button \(button) is cut vertically")
            }
        }
    }

    @Test func theWarningComesAfterTheButtonAndIsInsideTheRowToo() async {
        let rig = HelperRig(status: .notRegistered, runningApps: [FanHelperManager.macsFanControlBundleID])
        await rig.manager.refresh()
        for width in [CGFloat(216), 180, 150] {
            let parts = await frames(of: rig.manager, width: width)
            let button = parts[.button]
            let warning = parts[.warning]
            #expect(button != nil && warning != nil, "at \(width)")
            if let button, let warning {
                #expect(warning.minX >= button.maxX - 0.5, "at \(width): the warning is before the button")
                #expect(warning.maxX <= width + 0.5, "at \(width)")
            }
        }
    }

    @Test func theStatusGivesWayFirstAndTheButtonKeepsItsPlaceAtTheRightEdgeOfWhatIsLeft() async {
        let rig = HelperRig(status: .notRegistered)
        await rig.manager.refresh()
        let wide = await frames(of: rig.manager, width: 400)
        let narrow = await frames(of: rig.manager, width: 150)
        let (wideStatus, narrowStatus) = (wide[.status], narrow[.status])
        #expect(wideStatus != nil && narrowStatus != nil)
        #expect((narrowStatus?.width ?? 0) < (wideStatus?.width ?? 0), "the status is what shrinks")
        #expect(narrow[.button]?.width == wide[.button]?.width, "the button is not touched")
    }

    @Test func withoutTheWarningThereIsNoWarningFrame() async {
        let rig = HelperRig(status: .notRegistered)
        await rig.manager.refresh()
        #expect(await frames(of: rig.manager, width: 216)[.warning] == nil)
    }

    @Test func aRunningHelperOffersRemovalAsAButtonThatFitsToo() async {
        let rig = HelperRig(status: .enabled, runningApps: [FanHelperManager.macsFanControlBundleID])
        await rig.manager.refresh()
        let ideal = idealSize(of: "Gỡ")
        let button = await frames(of: rig.manager, width: 160)[.button]
        #expect(button != nil && button!.maxX <= 160.5 && button!.width >= ideal.width - 0.5)
    }
}
