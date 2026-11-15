import Darwin
import Foundation

nonisolated struct SystemCPUTicks: Equatable, Sendable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64
}

actor SystemCPUReader: CPUReading {
    private var lastTicks: SystemCPUTicks?
    private var lastProcessTimes: [Int32: (time: UInt64, date: Date)] = [:]
    private let processes: ProcessSource

    init(processes: ProcessSource = .live) {
        self.processes = processes
    }

    func read(topProcesses: Int) -> CPUSnapshot {
        let cpuUsage = readSystemCPU()
        let top = topProcesses > 0 ? readTopProcesses(limit: topProcesses) : []
        return CPUSnapshot(usagePercent: cpuUsage, processes: top)
    }

    private func readSystemCPU() -> Double? {
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let currentTicks = SystemCPUTicks(
            user: UInt64(cpuInfo.cpu_ticks.0),
            system: UInt64(cpuInfo.cpu_ticks.1),
            idle: UInt64(cpuInfo.cpu_ticks.2),
            nice: UInt64(cpuInfo.cpu_ticks.3)
        )
        defer { lastTicks = currentTicks }
        guard let prev = lastTicks else { return nil }
        return Self.calculatePercent(from: prev, to: currentTicks)
    }

    nonisolated static func calculatePercent(from prev: SystemCPUTicks, to current: SystemCPUTicks) -> Double {
        let userDiff = current.user >= prev.user ? current.user - prev.user : 0
        let systemDiff = current.system >= prev.system ? current.system - prev.system : 0
        let idleDiff = current.idle >= prev.idle ? current.idle - prev.idle : 0
        let niceDiff = current.nice >= prev.nice ? current.nice - prev.nice : 0
        let totalDiff = userDiff + systemDiff + idleDiff + niceDiff
        guard totalDiff > 0 else { return 0 }
        let activeDiff = userDiff + systemDiff + niceDiff
        return min(max(Double(activeDiff) / Double(totalDiff) * 100.0, 0), 100)
    }

    private func readTopProcesses(limit: Int) -> [ProcessCPU] {
        let now = Date()
        let pids = processes.pids().filter { $0 > 0 }
        var currentTimes: [Int32: (time: UInt64, date: Date)] = [:]
        var samples: [(pid: Int32, percent: Double)] = []

        for pid in pids {
            var info = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard status == 0 else { continue }
            let totalTime = info.ri_user_time + info.ri_system_time
            currentTimes[pid] = (totalTime, now)

            if let prev = lastProcessTimes[pid] {
                let dt = now.timeIntervalSince(prev.date)
                if dt > 0.5 && totalTime >= prev.time {
                    let dcpu = Double(totalTime - prev.time) / 1_000_000_000.0
                    let percent = (dcpu / dt) * 100.0
                    if percent > 0.05 {
                        samples.append((pid, percent))
                    }
                }
            }
        }
        lastProcessTimes = currentTimes

        let sorted = samples.sorted { ($0.percent, $1.pid) > ($1.percent, $0.pid) }.prefix(limit)
        return sorted.map { sample in
            let path = processes.path(sample.pid)
            let name = path.map { ($0 as NSString).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }
                ?? processes.name(sample.pid)
                ?? "Tiến trình \(sample.pid)"
            return ProcessCPU(pid: sample.pid, name: name, percent: sample.percent, path: path)
        }
    }
}
