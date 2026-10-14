import Foundation
import Testing
@testable import BatteryModule

@Suite struct LowPowerModeObserverTests {
    @Test func reportsEveryChangeUntilStopped() {
        let center = NotificationCenter()
        let observer = LowPowerModeObserver(center: center)
        nonisolated(unsafe) var changes = 0
        observer.start { changes += 1 }

        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        #expect(changes == 2)

        observer.stop()
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        #expect(changes == 2)
    }

    @Test func ignoresOtherNotifications() {
        let center = NotificationCenter()
        let observer = LowPowerModeObserver(center: center)
        nonisolated(unsafe) var changes = 0
        observer.start { changes += 1 }
        center.post(name: .init("SomethingElse"), object: nil)
        #expect(changes == 0)
        observer.stop()
    }

    @Test func startingAgainReplacesTheEarlierCallback() {
        let center = NotificationCenter()
        let observer = LowPowerModeObserver(center: center)
        nonisolated(unsafe) var first = 0
        nonisolated(unsafe) var second = 0
        observer.start { first += 1 }
        observer.start { second += 1 }
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        #expect(first == 0)
        #expect(second == 1)
        observer.stop()
    }

    @Test func stoppingWithoutStartingIsHarmless() {
        LowPowerModeObserver(center: NotificationCenter()).stop()
    }
}
