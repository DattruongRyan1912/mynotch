import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import FanHelperKit
@testable import PerformanceModule

@Suite("Performance Module Dashboard Telemetry Tests")
@MainActor
struct PerformanceDashboardTests {
    @Test("Snapshot returns .normal with placeholder summary when state is empty")
    func emptyStateReturnsNormal() {
        let rig = HelperRig()
        let module = PerformanceModule(
            thermal: FakeThermalReader(),
            memory: FakeMemoryReader(),
            cpu: FakeCPUReader(),
            helper: rig.manager,
            now: { Date() }
        )

        let snapshot = module.dashboardSnapshot()

        #expect(snapshot.status == DashboardStatusLevel.normal)
        #expect(snapshot.summary == "Đang đọc số liệu...")
    }

    @Test("Snapshot reports full metrics when data is present")
    func fullMetricsPopulated() {
        let rig = HelperRig()
        let module = PerformanceModule(
            thermal: FakeThermalReader(),
            memory: FakeMemoryReader(),
            cpu: FakeCPUReader(),
            helper: rig.manager,
            now: { Date() }
        )

        module.state.thermal = ThermalSnapshot(cpu: 65.0, gpu: 55.0, fans: [FanReading(index: 0, rpm: 2100, minRPM: 1200, maxRPM: 5000)])
        module.state.cpuUsage = 24.5
        module.state.usage = MemoryUsage(total: 32_000_000_000, used: 16_000_000_000, compressed: 0, swapUsed: 0, pressure: .normal)

        let snapshot = module.dashboardSnapshot()

        #expect(snapshot.status == DashboardStatusLevel.normal)
        #expect(snapshot.metrics.contains { $0.name == "CPU Nhiệt độ" })
        #expect(snapshot.metrics.contains { $0.name == "GPU Nhiệt độ" })
        #expect(snapshot.metrics.contains { $0.name == "CPU Usage" })
        #expect(snapshot.metrics.contains { $0.name == "RAM" })
        #expect(snapshot.metrics.contains { $0.name == "Quạt làm mát" })
        #expect(snapshot.summary.contains("CPU 65°C"))
    }

    @Test("Snapshot reports .warning when CPU temperature exceeds 85°C")
    func highTempReportsWarning() {
        let rig = HelperRig()
        let module = PerformanceModule(
            thermal: FakeThermalReader(),
            memory: FakeMemoryReader(),
            cpu: FakeCPUReader(),
            helper: rig.manager,
            now: { Date() }
        )

        module.state.thermal = ThermalSnapshot(cpu: 88.0, gpu: 70.0, fans: [])

        let snapshot = module.dashboardSnapshot()
        #expect(snapshot.status == DashboardStatusLevel.warning)
    }

    @Test("Processes demand is not activated solely by isDashboardActive")
    func dashboardDoesNotDemandProcesses() async {
        let rig = HelperRig()
        let module = PerformanceModule(
            thermal: FakeThermalReader(),
            memory: FakeMemoryReader(),
            cpu: FakeCPUReader(),
            helper: rig.manager,
            now: { Date() }
        )

        module.setDashboardActive(true)
        #expect(module.isDashboardActive == true)

        // Stop resets the flag
        await module.stop()
        #expect(module.isDashboardActive == false)
    }
}
