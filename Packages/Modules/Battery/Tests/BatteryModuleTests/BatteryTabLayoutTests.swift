import AppKit
import NotchUI
import SwiftUI
import Testing
@testable import BatteryModule

@Suite struct BatteryTabLayoutTests {
    /// What the tab leaves for its content: the notch pads the bottom, and two or more tabs bring the tab bar.
    private var contentHeight: CGFloat { BatteryTabView.preferredHeight - NotchTokens.padding - BatteryTabView.tabBarHeight }

    private func fittingHeight(_ snapshot: PowerSourceSnapshot, details: BatteryDetails?, lowPowerMode: Bool, width: CGFloat) -> CGFloat {
        let state = BatteryState()
        state.snapshot = snapshot
        state.details = details
        state.isLowPowerMode = lowPowerMode
        let tab = BatteryTabView(state: state, actions: BatteryTabActions(appeared: {}, disappeared: {}))
        return NSHostingView(rootView: tab.frame(width: width)).fittingSize.height
    }

    @Test func theFullestRowFitsTheHeightTheTabDeclaresAtTheNarrowestNotch() {
        // The narrowest open notch is 480 pt wide, 28 of them padding.
        let height = fittingHeight(
            PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true, minutesToFull: 80),
            details: BatteryDetails(cycleCount: 312, healthPercent: 92, batteryWatts: 12, adapterWatts: 96),
            lowPowerMode: true, width: 452
        )
        #expect(height == contentHeight)
    }

    @Test func aSparseRowHasTheSameHeight() {
        let height = fittingHeight(PowerSourceSnapshot(percent: 55, isCharging: false, isOnAC: false), details: nil, lowPowerMode: false, width: 572)
        #expect(height == contentHeight)
    }

    @Test func calibrationStagesMaintainExactDeclaredHeightAtNarrowestNotch() {
        for stage in [BatteryCalibrationStage.topUp, .discharging, .recharging] {
            let state = BatteryState()
            state.snapshot = PowerSourceSnapshot(percent: 80, isCharging: true, isOnAC: true, minutesToFull: 80)
            state.details = BatteryDetails(cycleCount: 312, healthPercent: 92, batteryWatts: 12, adapterWatts: 96)
            state.calibrationStage = stage
            state.isDischargeActive = (stage == .discharging)
            let tab = BatteryTabView(state: state, actions: BatteryTabActions(appeared: {}, disappeared: {}))
            let height = NSHostingView(rootView: tab.frame(width: 452)).fittingSize.height
            #expect(height == contentHeight)
        }
    }
}
