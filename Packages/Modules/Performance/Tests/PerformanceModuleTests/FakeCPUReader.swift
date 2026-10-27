@testable import PerformanceModule

/// A CPU reader that answers with what the test set and records how many processes each read asked for.
actor FakeCPUReader: CPUReading {
    private(set) var limits: [Int] = []
    private var snapshot: CPUSnapshot

    init(_ snapshot: CPUSnapshot = FakeCPUReader.defaultSnapshot) {
        self.snapshot = snapshot
    }

    static let defaultSnapshot = CPUSnapshot(
        usagePercent: 18.5,
        processes: [
            ProcessCPU(pid: 500, name: "Docker", percent: 42.1, path: "/Applications/Docker.app/Contents/MacOS/Docker"),
            ProcessCPU(pid: 501, name: "Xcode", percent: 25.3, path: "/Applications/Xcode.app/Contents/MacOS/Xcode"),
            ProcessCPU(pid: 502, name: "agy", percent: 12.0, path: nil),
            ProcessCPU(pid: 503, name: "WindowServer", percent: 8.4, path: nil),
            ProcessCPU(pid: 504, name: "Finder", percent: 2.1, path: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder"),
        ]
    )

    var reads: Int { limits.count }

    func answer(with snapshot: CPUSnapshot) { self.snapshot = snapshot }

    func read(topProcesses: Int) -> CPUSnapshot {
        limits.append(topProcesses)
        return CPUSnapshot(usagePercent: snapshot.usagePercent, processes: Array(snapshot.processes.prefix(topProcesses)))
    }
}
