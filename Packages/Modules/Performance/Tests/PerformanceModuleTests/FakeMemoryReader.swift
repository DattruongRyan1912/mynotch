@testable import PerformanceModule

/// A memory reader that answers with what the test set and records how many processes each read asked for.
actor FakeMemoryReader: MemoryReading {
    private(set) var limits: [Int] = []
    private var snapshot: MemorySnapshot

    init(_ snapshot: MemorySnapshot = FakeMemoryReader.busy) {
        self.snapshot = snapshot
    }

    static let gigabyte: UInt64 = 1 << 30

    static let usage = MemoryUsage(
        total: 32 * gigabyte, used: 20 * gigabyte, compressed: 3 * gigabyte, swapUsed: 2 * gigabyte, pressure: .normal
    )

    static let busy = MemorySnapshot(
        usage: usage,
        processes: [
            ProcessMemory(pid: 500, name: "Safari", footprint: 4 * gigabyte, path: "/Applications/Safari.app/Contents/MacOS/Safari"),
            ProcessMemory(pid: 501, name: "Xcode", footprint: 3 * gigabyte, path: "/Applications/Xcode.app/Contents/MacOS/Xcode"),
            ProcessMemory(pid: 502, name: "python3.11", footprint: 2 * gigabyte, path: "/usr/local/bin/python3.11"),
            ProcessMemory(pid: 503, name: "Slack", footprint: gigabyte, path: nil),
            ProcessMemory(pid: 504, name: "Mail", footprint: gigabyte / 2, path: nil),
            ProcessMemory(pid: 505, name: "Notes", footprint: gigabyte / 4, path: nil),
        ]
    )

    var reads: Int { limits.count }

    func answer(with snapshot: MemorySnapshot) { self.snapshot = snapshot }

    func read(topProcesses: Int) -> MemorySnapshot {
        limits.append(topProcesses)
        return MemorySnapshot(usage: snapshot.usage, processes: Array(snapshot.processes.prefix(topProcesses)))
    }
}
