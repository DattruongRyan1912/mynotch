import Darwin
import Foundation

/// Reads the memory of the Mac and its heaviest processes; faked in tests. Whatever it does is off the main actor.
nonisolated protocol MemoryReading: Sendable {
    /// `topProcesses` is how many of the heaviest processes to list; 0 skips walking the process list, which is the costly part.
    func read(topProcesses: Int) async -> MemorySnapshot
}

/// Reads through the VM statistics, `sysctl` and `libproc`: all readable without special rights, and none of it needs a helper. An
/// actor, so the calls never run on the main actor and never overlap.
actor SystemMemoryReader: MemoryReading {
    private let processes: ProcessSource

    init(processes: ProcessSource = .live) {
        self.processes = processes
    }

    func read(topProcesses: Int) -> MemorySnapshot {
        MemorySnapshot(usage: Self.usage(), processes: ProcessRanking.top(topProcesses, from: processes))
    }

    private static func usage() -> MemoryUsage? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let status = withUnsafeMutablePointer(to: &statistics) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        var pageSize: vm_size_t = 0
        guard status == KERN_SUCCESS, host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return nil }
        return MemoryUsage(
            total: ProcessInfo.processInfo.physicalMemory, counters: VMCounters(statistics), pageSize: UInt64(pageSize),
            swapUsed: swapUsed(), pressure: pressure()
        )
    }

    /// 0 when the system does not say; a Mac that does not swap says 0 as well.
    private static func swapUsed() -> UInt64 {
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        return sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 ? swap.xsu_used : 0
    }

    private static func pressure() -> MemoryPressure? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return nil }
        return MemoryPressure(level: Int(level))
    }
}
