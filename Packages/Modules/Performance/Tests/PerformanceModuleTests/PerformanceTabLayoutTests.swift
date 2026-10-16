import AppKit
import MyNotchCore
import NotchUI
import SwiftUI
import Testing
@testable import PerformanceModule

@Suite struct PerformanceTabLayoutTests {
    /// What the tab leaves for its content: the notch pads the bottom, and two or more tabs bring the tab bar.
    private var contentHeight: CGFloat { PerformanceTabView.preferredHeight - NotchTokens.padding - PerformanceTabView.tabBarHeight }

    /// A helper in each place it can be, driven the way the app does: by what the (fake) registration and helper say.
    static let helperRigs: [(name: String, rig: @MainActor () -> HelperRig)] = [
        ("not installed", { HelperRig(status: .notRegistered) }),
        ("needs approval", { HelperRig(status: .requiresApproval) }),
        ("running", { HelperRig(status: .enabled) }),
        ("unreachable", { HelperRig(status: .enabled, pings: [.failure(.timeout)]) }),
        ("needs approval, Macs Fan Control running", { HelperRig(status: .requiresApproval, runningApps: [FanHelperManager.macsFanControlBundleID]) }),
        ("not found", { HelperRig(status: .notFound) }),
    ]

    /// Everything the tab can show at once: both fans, the whole history, memory, five processes, and the helper's line.
    @MainActor static func state(
        fans: Int = 2, names: [String] = ["Safari", "Xcode", "python3.11", "Slack", "Mail"], thermal: Bool = true,
        helper: HelperRig? = HelperRig(status: .requiresApproval, runningApps: [FanHelperManager.macsFanControlBundleID])
    ) async -> PerformanceState {
        let state = PerformanceState()
        if let helper {
            await helper.manager.refresh()
            state.helper = helper.manager
        }
        state.hasThermal = thermal
        let start = Date(timeIntervalSinceReferenceDate: 9_000)
        for step in 0..<60 { state.history.append(60 + Double(step % 25), at: start.addingTimeInterval(Double(step) * 2)) }
        state.thermal = ThermalSnapshot(
            cpu: 84.4, gpu: 69.1,
            fans: [
                FanReading(index: 0, rpm: 5230.2, minRPM: 1200, maxRPM: 5779),
                FanReading(index: 1, rpm: 6002.2, minRPM: 1200, maxRPM: 6241),
            ].prefix(fans).map { $0 }
        )
        state.usage = FakeMemoryReader.usage
        state.processes = names.enumerated().map { index, name in
            ProcessRow(id: Int32(index + 1), name: name, size: MemoryFormat.bytes(FakeMemoryReader.gigabyte * UInt64(5 - index)), icon: nil)
        }
        return state
    }

    private func fittingHeight(of view: some View, width: CGFloat) -> CGFloat {
        NSHostingView(rootView: view.frame(width: width)).fittingSize.height
    }

    private func naturalWidth(of view: some View) -> CGFloat {
        NSHostingView(rootView: view.fixedSize()).fittingSize.width
    }

    static let halfWidth = (452 - PerformanceColumns.spacing) / 2

    @Test func theFullestContentFitsTheHeightTheTabDeclaresAtTheNarrowestNotch() async {
        // The narrowest open notch is 480 pt wide, 28 of them padding.
        #expect(fittingHeight(of: PerformanceColumns(state: await Self.state()), width: 452) <= contentHeight)
    }

    @Test func theDeclaredHeightIsNotMuchMoreThanTheContentNeeds() async {
        #expect(fittingHeight(of: PerformanceColumns(state: await Self.state()), width: 452) > contentHeight - 16)
    }

    @Test func theTabFitsWhatANotchAllows() {
        #expect(NotchTab.heightRange.contains(PerformanceTabView.preferredHeight))
    }

    @Test func eachColumnFitsInHalfTheNarrowestNotchWhateverTheHelperSays() async {
        for (name, rig) in Self.helperRigs {
            let state = await Self.state(helper: rig())
            #expect(fittingHeight(of: ThermalColumn(state: state), width: Self.halfWidth) <= contentHeight, "\(name)")
            #expect(fittingHeight(of: MemoryColumn(state: state), width: Self.halfWidth) <= contentHeight)
        }
    }

    @Test func theHelpersLineIsOneLineInHalfTheNarrowestNotchWithNothingCutOff() async {
        for (name, rig) in Self.helperRigs {
            let manager = rig().manager
            await manager.refresh()
            let row = FanHelperRow(helper: manager)
            #expect(naturalWidth(of: row) <= Self.halfWidth, "\(name): \(naturalWidth(of: row))")
            #expect(fittingHeight(of: row, width: Self.halfWidth) == FanHelperRow.height, "\(name)")
        }
    }

    @Test func aMacWithoutSensorsShowsTheMemoryAlone() async {
        let state = await Self.state(thermal: false)
        #expect(fittingHeight(of: PerformanceColumns(state: state), width: 452) <= contentHeight)
        #expect(fittingHeight(of: PerformanceColumns(state: state), width: 452) == fittingHeight(of: MemoryColumn(state: state), width: 452))
    }

    @Test func aMacWithoutFansHasNoHelperLineAndNeedsLessHeight() async {
        let none = await Self.state(fans: 0)
        let full = await Self.state()
        #expect(fittingHeight(of: ThermalColumn(state: none), width: Self.halfWidth) < fittingHeight(of: ThermalColumn(state: full), width: Self.halfWidth) - 20)
    }

    @Test func aLongProcessNameIsCutNotWrapped() async {
        let long = "com.apple.Virtualization.VirtualMachine.with.a.very.long.name"
        let names = [long, long, long, long, long]
        #expect(fittingHeight(of: MemoryColumn(state: await Self.state(names: names)), width: Self.halfWidth)
            == fittingHeight(of: MemoryColumn(state: await Self.state()), width: Self.halfWidth))
    }

    @Test func nothingReadYetStillFits() {
        let state = PerformanceState()
        state.hasThermal = true
        #expect(fittingHeight(of: PerformanceColumns(state: state), width: 452) <= contentHeight)
    }
}
