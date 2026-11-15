import Testing
@testable import PerformanceModule

@Suite struct CPUUsageTests {
    @Test func calculatePercentCalculatesActiveRatioAccurately() {
        let prev = SystemCPUTicks(user: 100, system: 50, idle: 800, nice: 50)
        let current = SystemCPUTicks(user: 120, system: 60, idle: 870, nice: 50)
        // delta: user = 20, system = 10, idle = 70, nice = 0 -> total = 100, active = 30
        let percent = SystemCPUReader.calculatePercent(from: prev, to: current)
        #expect(abs(percent - 30.0) < 0.001)
    }

    @Test func calculatePercentHandlesZeroDeltaGracefully() {
        let prev = SystemCPUTicks(user: 100, system: 50, idle: 800, nice: 50)
        let current = SystemCPUTicks(user: 100, system: 50, idle: 800, nice: 50)
        let percent = SystemCPUReader.calculatePercent(from: prev, to: current)
        #expect(percent == 0.0)
    }

    @Test func calculatePercentHandlesTickUnderflowOrReboot() {
        let prev = SystemCPUTicks(user: 500, system: 500, idle: 1000, nice: 0)
        let current = SystemCPUTicks(user: 10, system: 10, idle: 20, nice: 0)
        // All current < prev -> diffs are 0 -> total = 0 -> returns 0
        let percent = SystemCPUReader.calculatePercent(from: prev, to: current)
        #expect(percent == 0.0)
    }

    @Test func processIdentityFormatsCPUPercentageRowsCorrectly() {
        let identity = ProcessIdentity()
        let processes = [
            ProcessCPU(pid: 101, name: "Docker", percent: 42.14, path: "/Applications/Docker.app/Contents/MacOS/Docker"),
            ProcessCPU(pid: 102, name: "KernelTask", percent: 9.87, path: nil),
        ]
        let rows = identity.rows(for: processes)
        #expect(rows.count == 2)
        #expect(rows[0].name == "Docker")
        #expect(rows[0].size == "42.1%")
        #expect(rows[1].name == "KernelTask")
        #expect(rows[1].size == "9.9%")
    }
}
