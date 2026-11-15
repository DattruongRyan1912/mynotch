import Foundation
import Testing
@testable import BatteryModule

private final class PercentBox {
    var value: Int
    init(_ value: Int) {
        self.value = value
    }
}

@Suite @MainActor struct BatterySleepGuardTests {
    @Test func alertsWhenSleepDrainMeetsOrEqualToThreshold() {
        var alerts: [(drain: Int, duration: TimeInterval)] = []
        let fakeNC = NotificationCenter()

        let percentBox = PercentBox(85)
        let guardInstance = BatterySleepGuard(
            thresholdPercent: 3,
            readPercent: { percentBox.value },
            notificationCenter: fakeNC,
            onDrainAlert: { drain, duration in alerts.append((drain, duration)) }
        )

        let sleepDate = Date(timeIntervalSince1970: 1000)
        guardInstance.handleWillSleep(at: sleepDate)

        // Drain occurs: 85 -> 81 (4% drain >= 3% threshold)
        percentBox.value = 81
        let wakeDate = Date(timeIntervalSince1970: 1000 + 3600)
        guardInstance.handleDidWake(at: wakeDate)

        #expect(alerts.count == 1)
        #expect(alerts.first?.drain == 4)
        #expect(alerts.first?.duration == 3600)
    }

    @Test func doesNotAlertWhenDrainIsBelowThreshold() {
        var alerts: [(drain: Int, duration: TimeInterval)] = []
        let fakeNC = NotificationCenter()

        let percentBox = PercentBox(85)
        let guardInstance = BatterySleepGuard(
            thresholdPercent: 3,
            readPercent: { percentBox.value },
            notificationCenter: fakeNC,
            onDrainAlert: { drain, duration in alerts.append((drain, duration)) }
        )

        guardInstance.handleWillSleep(at: Date())

        // Minor drain: 85 -> 84 (1% drain < 3%)
        percentBox.value = 84
        guardInstance.handleDidWake(at: Date().addingTimeInterval(1800))

        #expect(alerts.isEmpty)
    }

    @Test func doesNotAlertWhenBatteryChargedDuringSleep() {
        var alerts: [(drain: Int, duration: TimeInterval)] = []
        let fakeNC = NotificationCenter()

        let percentBox = PercentBox(50)
        let guardInstance = BatterySleepGuard(
            thresholdPercent: 3,
            readPercent: { percentBox.value },
            notificationCenter: fakeNC,
            onDrainAlert: { drain, duration in alerts.append((drain, duration)) }
        )

        guardInstance.handleWillSleep(at: Date())

        // Charged on AC during sleep: 50 -> 90
        percentBox.value = 90
        guardInstance.handleDidWake(at: Date().addingTimeInterval(3600))

        #expect(alerts.isEmpty)
    }

    @Test func stopClearsStateAndNoAlertFires() {
        var alerts: [(drain: Int, duration: TimeInterval)] = []
        let fakeNC = NotificationCenter()

        let percentBox = PercentBox(80)
        let guardInstance = BatterySleepGuard(
            thresholdPercent: 3,
            readPercent: { percentBox.value },
            notificationCenter: fakeNC,
            onDrainAlert: { drain, duration in alerts.append((drain, duration)) }
        )

        guardInstance.handleWillSleep(at: Date())
        guardInstance.stop()

        percentBox.value = 60
        guardInstance.handleDidWake(at: Date().addingTimeInterval(100))

        #expect(alerts.isEmpty)
    }

    @Test func willSleepNotificationFiresHookToCancelDischarge() {
        var hookFired = false
        let fakeNC = NotificationCenter()
        let guardInstance = BatterySleepGuard(
            thresholdPercent: 3,
            readPercent: { 80 },
            notificationCenter: fakeNC,
            onDrainAlert: { _, _ in }
        )
        guardInstance.onWillSleep = {
            hookFired = true
        }
        guardInstance.handleWillSleep()
        #expect(hookFired)
    }
}
