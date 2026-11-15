import Foundation
import SwiftUI
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

/// Fake module conforming to DashboardReporting for telemetry verification.
@MainActor
private final class FakeReportingModule: FeatureModule, DashboardReporting {
    let descriptor: ModuleDescriptor
    var snapshotToReturn: DashboardSnapshot?
    var isActiveReceived: [Bool] = []

    init(_ id: ModuleID, order: Int = 1) {
        self.descriptor = ModuleDescriptor(
            id: id,
            displayName: "Fake \(id.rawValue)",
            systemImage: "star",
            defaultEnabled: true,
            order: order
        )
    }

    func start(_ context: ModuleContext) async throws(ModuleError) {}
    func stop() async {}
    func makeTab() -> NotchTab? { nil }
    func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? { nil }
    var menuItems: [ModuleMenuItem] { [] }

    func dashboardSnapshot() -> DashboardSnapshot {
        snapshotToReturn ?? DashboardSnapshot(
            moduleID: descriptor.id,
            title: descriptor.displayName,
            systemImage: descriptor.systemImage,
            status: .success,
            summary: "Reporting OK",
            metrics: [
                DashboardMetric(name: "Speed", value: .number(120, unit: "MB/s")),
            ]
        )
    }

    func setDashboardActive(_ active: Bool) {
        isActiveReceived.append(active)
    }
}

@Suite struct DashboardTelemetryTests {
    @Test func snapshotHoldsProvidedMetrics() {
        let metric = DashboardMetric(name: "CPU", value: .number(45.5, unit: "%"), systemImage: "cpu")
        let snapshot = DashboardSnapshot(
            moduleID: "test",
            title: "Test Module",
            systemImage: "gear",
            status: .warning,
            summary: "Warning test",
            metrics: [metric]
        )

        #expect(snapshot.id == "test")
        #expect(snapshot.moduleID == "test")
        #expect(snapshot.status == .warning)
        #expect(snapshot.summary == "Warning test")
        #expect(snapshot.metrics.count == 1)
        #expect(snapshot.metrics.first?.name == "CPU")
        #expect(snapshot.metrics.first?.value == .number(45.5, unit: "%"))
    }

    @Test func telemetryCenterInitiallyIdleAndPollsOnlyWhenVisible() async {
        let reporter = FakeReportingModule("reported", order: 1)
        let plain = FakeModule("plain", order: 2)
        let harness = Harness([reporter, plain])
        await harness.registry.bootstrap()

        let scheduler = harness.scheduler
        let center = DashboardTelemetryCenter(
            registry: harness.registry,
            scheduler: scheduler,
            pollInterval: .seconds(2)
        )

        #expect(!center.isWindowVisible)
        #expect(center.snapshots.isEmpty)
        #expect(reporter.isActiveReceived.isEmpty)

        // Make window visible
        center.setWindowVisible(true)
        #expect(center.isWindowVisible)
        #expect(reporter.isActiveReceived == [true])
        #expect(center.snapshots.count == 2)
        #expect(center.snapshots["reported"]?.summary == "Reporting OK")
        #expect(center.snapshots["plain"]?.status == .success)
        #expect(center.healthSummary.totalModules == 2)
        #expect(center.healthSummary.activeModules == 2)

        // Advancing scheduler triggers recurring refresh
        reporter.snapshotToReturn = DashboardSnapshot(
            moduleID: "reported",
            title: "Updated",
            systemImage: "star",
            status: .critical,
            summary: "Failed state"
        )
        scheduler.advance(by: .seconds(2))
        #expect(center.snapshots["reported"]?.summary == "Failed state")
        #expect(center.healthSummary.hasWarnings == true)

        // Closing window stops polling
        center.setWindowVisible(false)
        #expect(!center.isWindowVisible)
        #expect(reporter.isActiveReceived == [true, false])

        // Further timer advancement does not refresh
        reporter.snapshotToReturn = DashboardSnapshot(
            moduleID: "reported",
            title: "After close",
            systemImage: "star",
            summary: "Should not be read"
        )
        scheduler.advance(by: .seconds(10))
        #expect(center.snapshots["reported"]?.summary == "Failed state")
    }

    @Test func healthSummaryTracksDisabledAndPausedModules() async {
        let m1 = FakeModule("m1", order: 1)
        let m2 = FakeModule("m2", order: 2, defaultEnabled: false)
        let harness = Harness([m1, m2])
        await harness.registry.bootstrap()

        let center = DashboardTelemetryCenter(
            registry: harness.registry,
            scheduler: harness.scheduler
        )

        center.refresh()
        #expect(center.healthSummary.totalModules == 2)
        #expect(center.healthSummary.activeModules == 1)
        #expect(center.healthSummary.disabledModules == 1)
        #expect(center.healthSummary.pausedModules == 0)

        // Pause all
        await harness.registry.pauseAll()
        center.refresh()
        #expect(center.healthSummary.pausedModules == 1)
    }
}
