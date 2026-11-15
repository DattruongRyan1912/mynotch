import Foundation
import Testing
@testable import MyNotchCore

@Suite("Dashboard Toast Center Tests")
@MainActor
struct DashboardToastCenterTests {
    @Test("Test Case 1: Show toast and auto dismiss after duration")
    func testShowToastAndAutoDismiss() async throws {
        let center = DashboardToastCenter()
        #expect(center.currentToast == nil)

        center.show(message: "Đã lưu công việc", duration: 0.1)
        #expect(center.currentToast != nil)
        #expect(center.currentToast?.message == "Đã lưu công việc")

        var waited = 0
        while center.currentToast != nil && waited < 300 {
            try await Task.sleep(for: .milliseconds(20))
            waited += 20
        }
        #expect(center.currentToast == nil)
    }

    @Test("Test Case 2: Rapid show toast overrides previous and cancels previous dismiss timer")
    func testRapidShowToastOverridesPreviousAndCancelsTimer() async throws {
        let center = DashboardToastCenter()

        center.show(message: "Toast 1", duration: 0.2)
        #expect(center.currentToast?.message == "Toast 1")

        try await Task.sleep(for: .milliseconds(50))
        center.show(message: "Toast 2", duration: 0.2)

        try await Task.sleep(for: .milliseconds(50)) // t = 100ms
        #expect(center.currentToast?.message == "Toast 2")

        try await Task.sleep(for: .milliseconds(120)) // t = 220ms
        #expect(center.currentToast?.message == "Toast 2")

        // Chờ dismiss timer hoàn tất với margin an toàn cho test runner
        var waited = 0
        while center.currentToast != nil && waited < 300 {
            try await Task.sleep(for: .milliseconds(20))
            waited += 20
        }
        #expect(center.currentToast == nil)
    }
}
