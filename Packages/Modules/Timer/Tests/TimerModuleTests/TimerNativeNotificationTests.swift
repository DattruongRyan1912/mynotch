import Foundation
import Testing
@testable import TimerModule
import MyNotchCore
import MyNotchTestSupport

@Suite("Timer Native Notification Tests")
struct TimerNativeNotificationTests {
    @Test("Test Case 5: Countdown finish posts native notification")
    func testCountdownFinishPostsNativeNotification() async throws {
        let clock = FakeClock()
        let sound = FakeSoundPlayer()
        let mockPoster = MockNativeNotificationPoster()
        let module = TimerModule(now: { clock.date }, sound: sound, notificationPoster: mockPoster)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        module.startCountdown(minutes: 1, kind: .task, label: "Làm việc")
        clock.advance(60)
        harness.scheduler.advance(by: .seconds(60))

        try await Task.sleep(for: .milliseconds(50))

        #expect(mockPoster.postedNotifications.count == 1)
        #expect(mockPoster.postedNotifications.first?.id == "timer.finished")
        #expect(mockPoster.postedNotifications.first?.title.contains("Hết giờ") == true)
    }
}
