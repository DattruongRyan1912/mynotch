import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import BatteryModule

@Suite("Battery Module Dashboard Telemetry Tests")
@MainActor
struct BatteryDashboardTests {
    @Test("Snapshot returns .normal and placeholder when power source snapshot is nil")
    func nilSnapshotReturnsNormal() {
        let fake = FakePowerSource(nil)
        let module = BatteryModule(reader: fake)

        let snapshot = module.dashboardSnapshot()

        #expect(snapshot.status == DashboardStatusLevel.normal)
        #expect(snapshot.summary == "Không có dữ liệu pin")
        #expect(snapshot.metrics.contains { $0.name == "Trạng thái" })
    }

    @Test("Snapshot reports .critical on low battery without AC")
    func criticalBatteryReportsCorrectStatus() {
        let lowSnap = PowerSourceSnapshot(percent: 10, isCharging: false, isOnAC: false)
        let fake = FakePowerSource(lowSnap)
        let module = BatteryModule(reader: fake)
        module.state.snapshot = lowSnap

        let snapshot = module.dashboardSnapshot()
        #expect(snapshot.status == DashboardStatusLevel.critical)
        #expect(snapshot.summary.contains("10%"))
    }

    @Test("Snapshot reports .warning when battery is between 16% and 25% without AC")
    func warningBatteryReportsCorrectStatus() {
        let warnSnap = PowerSourceSnapshot(percent: 20, isCharging: false, isOnAC: false)
        let fake = FakePowerSource(warnSnap)
        let module = BatteryModule(reader: fake)
        module.state.snapshot = warnSnap

        let snapshot = module.dashboardSnapshot()
        #expect(snapshot.status == DashboardStatusLevel.warning)
    }

    @Test("Snapshot reports .success when charging or full on AC")
    func successWhenCharging() {
        let chargingSnap = PowerSourceSnapshot(percent: 60, isCharging: true, isOnAC: true)
        let fake = FakePowerSource(chargingSnap)
        let module = BatteryModule(reader: fake)
        module.state.snapshot = chargingSnap

        let snapshot = module.dashboardSnapshot()
        #expect(snapshot.status == DashboardStatusLevel.success)
    }

    @Test("Snapshot includes AlDente limit metric when enabled")
    func alDenteMetricWhenEnabled() {
        let snap = PowerSourceSnapshot(percent: 80, isCharging: false, isOnAC: true)
        let fake = FakePowerSource(snap)
        let module = BatteryModule(reader: fake)
        module.state.snapshot = snap
        module.state.isLimitToEightyEnabled = true

        let snapshot = module.dashboardSnapshot()
        #expect(snapshot.metrics.contains { $0.name == "Khóa sạc 80%" })
    }
}
