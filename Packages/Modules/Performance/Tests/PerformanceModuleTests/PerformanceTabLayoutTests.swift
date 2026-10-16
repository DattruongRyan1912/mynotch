import AppKit
import MyNotchCore
import NotchUI
import SwiftUI
import Testing
@testable import PerformanceModule

@Suite struct PerformanceTabLayoutTests {
    /// What the tab leaves for its content: the notch pads the bottom, and two or more tabs bring the tab bar.
    private var contentHeight: CGFloat { PerformanceTabView.preferredHeight - NotchTokens.padding - PerformanceTabView.tabBarHeight }

    /// Everything the tab can show at once: both fans, the whole history, memory, and five processes.
    static func state(fans: Int = 2, names: [String] = ["Safari", "Xcode", "python3.11", "Slack", "Mail"], thermal: Bool = true) -> PerformanceState {
        let state = PerformanceState()
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

    @Test func theFullestContentFitsTheHeightTheTabDeclaresAtTheNarrowestNotch() {
        // The narrowest open notch is 480 pt wide, 28 of them padding.
        #expect(fittingHeight(of: PerformanceColumns(state: Self.state()), width: 452) <= contentHeight)
    }

    @Test func theDeclaredHeightIsNotMuchMoreThanTheContentNeeds() {
        #expect(fittingHeight(of: PerformanceColumns(state: Self.state()), width: 452) > contentHeight - 16)
    }

    @Test func theTabFitsWhatANotchAllows() {
        #expect(NotchTab.heightRange.contains(PerformanceTabView.preferredHeight))
    }

    @Test func eachColumnFitsInHalfTheNarrowestNotch() {
        let halfWidth = (452 - PerformanceColumns.spacing) / 2
        let state = Self.state()
        #expect(fittingHeight(of: ThermalColumn(state: state), width: halfWidth) <= contentHeight)
        #expect(fittingHeight(of: MemoryColumn(state: state), width: halfWidth) <= contentHeight)
    }

    @Test func aMacWithoutSensorsShowsTheMemoryAlone() {
        let state = Self.state(thermal: false)
        #expect(fittingHeight(of: PerformanceColumns(state: state), width: 452) <= contentHeight)
        #expect(fittingHeight(of: PerformanceColumns(state: state), width: 452) == fittingHeight(of: MemoryColumn(state: state), width: 452))
    }

    @Test func aMacWithoutFansNeedsNoMoreHeight() {
        #expect(fittingHeight(of: ThermalColumn(state: Self.state(fans: 0)), width: 215) < fittingHeight(of: ThermalColumn(state: Self.state()), width: 215))
    }

    @Test func aLongProcessNameIsCutNotWrapped() {
        let long = "com.apple.Virtualization.VirtualMachine.with.a.very.long.name"
        let names = [long, long, long, long, long]
        #expect(fittingHeight(of: MemoryColumn(state: Self.state(names: names)), width: 215) == fittingHeight(of: MemoryColumn(state: Self.state()), width: 215))
    }

    @Test func nothingReadYetStillFits() {
        let state = PerformanceState()
        state.hasThermal = true
        #expect(fittingHeight(of: PerformanceColumns(state: state), width: 452) <= contentHeight)
    }
}
