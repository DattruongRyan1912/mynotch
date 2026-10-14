import Foundation
import Testing
@testable import TimerModule

@Suite struct MinuteDialTests {
    // MARK: Angle and minutes

    @Test func everyMinuteIsSixDegreesClockwiseFromTheTop() {
        #expect(MinuteDial.angle(forMinutes: 0) == 0)
        #expect(MinuteDial.angle(forMinutes: 15) == 90)
        #expect(MinuteDial.angle(forMinutes: 30) == 180)
        #expect(MinuteDial.angle(forMinutes: 45) == 270)
        #expect(MinuteDial.angle(forMinutes: 60) == 360)
    }

    @Test func angleAndMinutesAreInverseForEveryWholeMinute() {
        for minutes in 1...59 {
            #expect(MinuteDial.minutes(forAngle: MinuteDial.angle(forMinutes: minutes), previous: minutes) == minutes)
        }
    }

    @Test func anAngleSnapsToTheNearestWholeMinute() {
        #expect(MinuteDial.minutes(forAngle: 90, previous: 0) == 15)
        #expect(MinuteDial.minutes(forAngle: 92.9, previous: 0) == 15)
        #expect(MinuteDial.minutes(forAngle: 93.1, previous: 0) == 16)
        #expect(MinuteDial.minutes(forAngle: 87.1, previous: 0) == 15)
        #expect(MinuteDial.minutes(forAngle: 86.9, previous: 0) == 14)
        #expect(MinuteDial.minutes(forAngle: 2.9, previous: 10) == 0)
        #expect(MinuteDial.minutes(forAngle: 3.1, previous: 10) == 1)
    }

    @Test func anAngleOutsideOneTurnWrapsAround() {
        #expect(MinuteDial.minutes(forAngle: 450, previous: 0) == 15)
        #expect(MinuteDial.minutes(forAngle: -90, previous: 0) == 45)
        #expect(MinuteDial.minutes(forAngle: 720 + 180, previous: 0) == 30)
    }

    @Test func theTopOfTheDialIsSixtyComingFromTheHighSideAndZeroComingFromTheLowSide() {
        // Dragging clockwise through 12 o'clock from 59 minutes ends on a full dial, not an empty one.
        #expect(MinuteDial.minutes(forAngle: 0, previous: 59) == 60)
        #expect(MinuteDial.minutes(forAngle: 359, previous: 59) == 60)
        #expect(MinuteDial.minutes(forAngle: 360, previous: 60) == 60)
        #expect(MinuteDial.minutes(forAngle: 0, previous: 30) == 60)
        // Dragging back to the top from the low side empties it.
        #expect(MinuteDial.minutes(forAngle: 0, previous: 1) == 0)
        #expect(MinuteDial.minutes(forAngle: 359, previous: 1) == 0)
        #expect(MinuteDial.minutes(forAngle: 0, previous: 29) == 0)
    }

    @Test func keepingDraggingPastTheTopWrapsFromSixtyToTheFirstMinutes() {
        var minutes = 58
        for angle in [354.0, 358, 0, 6, 12] {
            minutes = MinuteDial.minutes(forAngle: angle, previous: minutes)
        }
        #expect(minutes == 2)
    }

    // MARK: Pointer position

    @Test func aPointIsMeasuredClockwiseFromTwelveOClock() {
        let center = CGPoint(x: 50, y: 50)
        #expect(MinuteDial.angle(of: CGPoint(x: 50, y: 40), around: center) == 0)
        #expect(MinuteDial.angle(of: CGPoint(x: 60, y: 50), around: center) == 90)
        #expect(MinuteDial.angle(of: CGPoint(x: 50, y: 60), around: center) == 180)
        #expect(MinuteDial.angle(of: CGPoint(x: 40, y: 50), around: center) == 270)
        let diagonal = MinuteDial.angle(of: CGPoint(x: 60, y: 40), around: center)
        #expect(abs(diagonal - 45) < 0.0001)
    }

    @Test func thePointerOnTheCenterIsAtTheTop() {
        let center = CGPoint(x: 50, y: 50)
        #expect(MinuteDial.angle(of: center, around: center) == 0)
    }

    // MARK: Keyboard and VoiceOver steps

    @Test func arrowKeysStepOneMinuteAndShiftStepsFive() {
        #expect(MinuteDial.keyboardDelta(increase: true, shift: false) == 1)
        #expect(MinuteDial.keyboardDelta(increase: false, shift: false) == -1)
        #expect(MinuteDial.keyboardDelta(increase: true, shift: true) == 5)
        #expect(MinuteDial.keyboardDelta(increase: false, shift: true) == -5)
    }

    @Test func steppingStopsAtTheEndsInsteadOfWrapping() {
        #expect(MinuteDial.stepped(10, by: 1) == 11)
        #expect(MinuteDial.stepped(10, by: -5) == 5)
        #expect(MinuteDial.stepped(58, by: 5) == 60)
        #expect(MinuteDial.stepped(60, by: 1) == 60)
        #expect(MinuteDial.stepped(3, by: -5) == 0)
        #expect(MinuteDial.stepped(0, by: -1) == 0)
    }

    @Test func clampingKeepsAValueOnTheDial() {
        #expect(MinuteDial.clamped(-4) == 0)
        #expect(MinuteDial.clamped(25) == 25)
        #expect(MinuteDial.clamped(90) == 60)
    }

    // MARK: Scrolling

    @Test func aScrollIsAccumulatedUntilItAmountsToAWholeMinute() {
        var scroll = DialScroll()
        #expect(scroll.minutes(forTicks: 0.4) == 0)
        #expect(scroll.minutes(forTicks: 0.4) == 0)
        #expect(scroll.minutes(forTicks: 0.4) == 1)
        #expect(scroll.minutes(forTicks: 0.9) == 1)   // 0.2 + 0.9 = 1.1
        #expect(scroll.minutes(forTicks: -1.5) == -1) // 0.1 - 1.5 = -1.4
        #expect(scroll.minutes(forTicks: -0.7) == -1) // -0.4 - 0.7 = -1.1
    }

    @Test func aPreciseScrollMovesInSmallStepsAndAWheelNotchInWholeOnes() {
        #expect(DialScroll.ticks(forDelta: 16, isPrecise: true) == 2)
        #expect(DialScroll.ticks(forDelta: -4, isPrecise: true) == -0.5)
        #expect(DialScroll.ticks(forDelta: 3, isPrecise: false) == 3)
    }

    // MARK: Remaining time on the ring

    @Test func theRingShowsTheRemainingMinutesOutOfSixty() {
        #expect(MinuteDial.fraction(remaining: 1_800) == 0.5)
        #expect(MinuteDial.fraction(remaining: 3_600) == 1)
        #expect(MinuteDial.fraction(remaining: 0) == 0)
    }

    @Test func aTimerLongerThanAnHourOrBelowZeroStaysOnTheRing() {
        #expect(MinuteDial.fraction(remaining: 7_200) == 1)
        #expect(MinuteDial.fraction(remaining: -5) == 0)
    }

    // MARK: Spoken values

    @Test func voiceOverReadsTheMinutesLeftRoundedUp() {
        #expect(MinuteDial.spokenRemaining(seconds: 12 * 60) == "còn 12 phút")
        #expect(MinuteDial.spokenRemaining(seconds: 11 * 60 + 1) == "còn 12 phút")
        #expect(MinuteDial.spokenRemaining(seconds: 60) == "còn 1 phút")
        #expect(MinuteDial.spokenRemaining(seconds: 75 * 60) == "còn 75 phút")
    }

    @Test func voiceOverReadsTheLastMinuteAndTheEndInWords() {
        #expect(MinuteDial.spokenRemaining(seconds: 59) == "còn dưới 1 phút")
        #expect(MinuteDial.spokenRemaining(seconds: 0.5) == "còn dưới 1 phút")
        #expect(MinuteDial.spokenRemaining(seconds: 0) == "hết giờ")
        #expect(MinuteDial.spokenRemaining(seconds: -3) == "hết giờ")
    }

    @Test func voiceOverReadsTheMinutesBeingSet() {
        #expect(MinuteDial.spokenSetting(minutes: 25) == "25 phút")
        #expect(MinuteDial.spokenSetting(minutes: 0) == "0 phút")
    }
}
