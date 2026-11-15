import Foundation
import Testing
@testable import BatteryModule
import MyNotchCore
import MyNotchTestSupport

@Suite("Battery Native Notification Tests")
struct BatteryNativeNotificationTests {
    @Test("Test Case 3: Battery limit notification fired on transition to 80% and not spammed on repeated polls")
    func testBatteryLimitNotificationFiredOnTransitionOnly() async throws {
        let mockPoster = MockNativeNotificationPoster()
        let initialSnapshot = PowerSourceSnapshot(
            percent: 79,
            isCharging: true,
            isOnAC: true,
            isAttachedToAdapter: true,
            minutesToEmpty: nil,
            minutesToFull: 5
        )
        let source = FakePowerSource(initialSnapshot)
        let module = BatteryModule(reader: source, notificationPoster: mockPoster)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        #expect(mockPoster.postedNotifications.isEmpty)

        // Snapshot 2: Chuyển sang 80% trên AC -> Bắn đúng 1 lần
        source.emit(PowerSourceSnapshot(
            percent: 80,
            isCharging: true,
            isOnAC: true,
            isAttachedToAdapter: true,
            minutesToEmpty: nil,
            minutesToFull: 0
        ))
        try await Task.sleep(for: .milliseconds(50))
        #expect(mockPoster.postedNotifications.count == 1)
        #expect(mockPoster.postedNotifications.first?.title.contains("80%") == true || mockPoster.postedNotifications.first?.body.contains("80%") == true)

        // Snapshot 3: Tiếp tục poll nhận 80% trên AC -> KHÔNG spam thông báo
        source.emit(PowerSourceSnapshot(
            percent: 80,
            isCharging: true,
            isOnAC: true,
            isAttachedToAdapter: true,
            minutesToEmpty: nil,
            minutesToFull: 0
        ))
        try await Task.sleep(for: .milliseconds(50))
        #expect(mockPoster.postedNotifications.count == 1)
    }

    @Test("Test Case 4: Battery heat protection notification fired on high temperature >= 34°C")
    func testBatteryHeatProtectionNotificationFiredOnHighTemp() async throws {
        let mockPoster = MockNativeNotificationPoster()
        let initialSnapshot = PowerSourceSnapshot(
            percent: 60,
            isCharging: true,
            isOnAC: true,
            isAttachedToAdapter: true,
            minutesToEmpty: nil,
            minutesToFull: 30
        )
        let source = FakePowerSource(initialSnapshot)
        let module = BatteryModule(reader: source, notificationPoster: mockPoster)
        let harness = RegistryHarness([module])
        await harness.registry.bootstrap()

        // Cập nhật nhiệt độ cao >= 34°C
        let highTempDetails = BatteryDetails(
            cycleCount: 100,
            healthPercent: 98,
            batteryWatts: 24.0,
            adapterWatts: 60,
            temperatureCelsius: 34.5
        )
        module.updateDetailsForTest(highTempDetails)
        try await Task.sleep(for: .milliseconds(50))

        #expect(mockPoster.postedNotifications.count == 1)
        #expect(mockPoster.postedNotifications.first?.title.contains("Nhiệt độ") == true || mockPoster.postedNotifications.first?.body.contains("34") == true)

        // Cập nhật nhiệt độ hạ về 31°C -> Không spam thêm thông báo lỗi
        let normalTempDetails = BatteryDetails(
            cycleCount: 100,
            healthPercent: 98,
            batteryWatts: 24.0,
            adapterWatts: 60,
            temperatureCelsius: 31.0
        )
        module.updateDetailsForTest(normalTempDetails)
        try await Task.sleep(for: .milliseconds(50))
        #expect(mockPoster.postedNotifications.count == 1)
    }
}
