import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import PerformanceModule

@Suite struct PerformanceTabLayoutTests {
    /// What the tab leaves for its content: the notch pads the bottom, and two or more tabs bring the tab bar.
    private var contentHeight: CGFloat { PerformanceTabView.preferredHeight - NotchTokens.padding - PerformanceTabView.tabBarHeight }

    static func state(fans: Int = 2) -> PerformanceState {
        let state = PerformanceState()
        let start = Date(timeIntervalSinceReferenceDate: 9_000)
        for step in 0..<60 { state.history.append(60 + Double(step % 25), at: start.addingTimeInterval(Double(step) * 2)) }
        state.thermal = ThermalSnapshot(
            cpu: 84.4, gpu: 69.1,
            fans: [
                FanReading(index: 0, rpm: 5230.2, minRPM: 1200, maxRPM: 5779),
                FanReading(index: 1, rpm: 6002.2, minRPM: 1200, maxRPM: 6241),
            ].prefix(fans).map { $0 }
        )
        return state
    }

    private func fittingHeight(of state: PerformanceState, width: CGFloat) -> CGFloat {
        NSHostingView(rootView: ThermalColumn(state: state).frame(width: width)).fittingSize.height
    }

    @Test func theFullestContentFitsTheHeightTheTabDeclaresAtTheNarrowestNotch() {
        // The narrowest open notch is 480 pt wide, 28 of them padding.
        #expect(fittingHeight(of: Self.state(), width: 452) <= contentHeight)
    }

    @Test func theContentStillFitsInHalfTheWidthForWhenAColumnSharesTheTab() {
        #expect(fittingHeight(of: Self.state(), width: 215) <= contentHeight)
    }

    @Test func theDeclaredHeightIsNotMuchMoreThanTheContentNeeds() {
        #expect(fittingHeight(of: Self.state(), width: 452) > contentHeight - 16)
    }

    @Test func aMacWithoutFansNeedsLess() {
        #expect(fittingHeight(of: Self.state(fans: 0), width: 452) < fittingHeight(of: Self.state(), width: 452))
    }

    @Test func nothingReadYetStillFits() {
        #expect(fittingHeight(of: PerformanceState(), width: 452) <= contentHeight)
    }
}
