import CoreGraphics
import Testing
@testable import BatteryModule

@Suite struct BatteryGaugeLayoutTests {
    /// A body 500 pt wide has an inner width of 490: the outline (2) and the inset (3) on each side.
    private func layout(_ percent: Int, bodyWidth: CGFloat = 500) -> BatteryGaugeLayout {
        BatteryGaugeLayout(percent: percent, bodyWidth: bodyWidth)
    }

    @Test func theFillGrowsWithThePercentOfTheInnerWidth() {
        #expect(layout(100).innerWidth == 490)
        #expect(layout(100).fillWidth == 490)
        #expect(layout(50).fillWidth == 245)
        #expect(layout(80).fillWidth == 392)
    }

    @Test func anEmptyBatteryHasNoFillButALowOneStaysVisible() {
        #expect(layout(0).fillWidth == 0)
        let sliver = layout(1)   // 1 % of 490 is under 5 pt
        #expect(sliver.fillWidth == BatteryGaugeLayout.minimumFillWidth)
        #expect(BatteryGaugeLayout.minimumFillWidth == 14)
    }

    @Test func thePercentIsClampedAndTheFillNeverOutgrowsTheBody() {
        #expect(layout(140).fillWidth == 490)
        #expect(layout(-5).fillWidth == 0)
        let narrow = layout(1, bodyWidth: 20)   // inner width 10: less than the minimum
        #expect(narrow.fillWidth == 10)
        #expect(layout(50, bodyWidth: 4).fillWidth == 0)
    }

    @Test func theNumberFitsInsideWhenTheFillHasRoomForItAndItsMargins() {
        // The label's width plus 10 pt before it and 10 pt after it.
        #expect(layout(50).labelFitsInside(labelWidth: 80))      // 245 >= 100
        #expect(layout(100).labelFitsInside(labelWidth: 110))    // 490 >= 130
        #expect(!layout(10).labelFitsInside(labelWidth: 80))     // 49 < 100
        #expect(!layout(0).labelFitsInside(labelWidth: 60))
    }

    @Test func theNumberFitsExactlyAtTheMargins() {
        let fill = layout(50).fillWidth   // 245
        #expect(layout(50).labelFitsInside(labelWidth: fill - 20))
        #expect(!layout(50).labelFitsInside(labelWidth: fill - 19.9))
    }

    @Test func aNumberInsideEndsTenPointsBeforeTheFillsEnd() {
        let expected: CGFloat = 245 - 80 - 10   // the fill's width, the number's width, the margin
        #expect(layout(50).labelOffset(labelWidth: 80) == expected)
    }

    @Test func aNumberOutsideStartsTenPointsAfterTheFillsEnd() {
        let expected: CGFloat = 49 + 10   // the fill's width (the number does not fit in it), the margin
        #expect(layout(10).labelOffset(labelWidth: 80) == expected)
        #expect(layout(0).labelOffset(labelWidth: 60) == 10)
    }
}

@Suite struct BatteryGaugeMotionTests {
    @Test func theHighlightSweepsOnlyWhileChargingVisibleAndMotionIsAllowed() {
        #expect(BatteryGaugeMotion.isSweeping(isCharging: true, isTabVisible: true, reduceMotion: false))
        #expect(!BatteryGaugeMotion.isSweeping(isCharging: false, isTabVisible: true, reduceMotion: false))
        #expect(!BatteryGaugeMotion.isSweeping(isCharging: true, isTabVisible: false, reduceMotion: false))
        #expect(!BatteryGaugeMotion.isSweeping(isCharging: true, isTabVisible: true, reduceMotion: true))
        #expect(!BatteryGaugeMotion.isSweeping(isCharging: false, isTabVisible: false, reduceMotion: true))
    }

    @Test func theSweepRepeatsEveryTwoPointSixSeconds() {
        #expect(BatteryGaugeMotion.sweepPeriod == 2.6)
        #expect(BatteryGaugeMotion.sweepPhase(at: 0) == 0)
        #expect(abs(BatteryGaugeMotion.sweepPhase(at: 1.3) - 0.5) < 1e-9)
        #expect(abs(BatteryGaugeMotion.sweepPhase(at: 2.6 * 40 + 0.65) - 0.25) < 1e-6)
    }
}
