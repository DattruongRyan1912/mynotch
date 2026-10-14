import Darwin

/// The real process table: `libproc` for who started whom, and the kernel's argument block for the command line.
/// Needs no privilege for the current user's own processes. Terminating is a plain `kill`.
struct SystemProcessTable: ProcessTable {
    func processes(withParent parent: pid_t) -> [ProcessEntry] {
        let expected = proc_listallpids(nil, 0)
        guard expected > 0 else { return [] }
        // Room for processes that start in between.
        var pids = [pid_t](repeating: 0, count: Int(expected) * 2)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard count > 0 else { return [] }
        return pids.prefix(Int(count)).compactMap { entry(pid: $0, parent: parent) }
    }

    func terminate(_ pid: pid_t) {
        kill(pid, SIGTERM)
    }

    /// nil for a process that is not the user's (whose command line cannot be read anyway), has another parent, or ended
    /// meanwhile. The command line is read only for the processes that are wanted.
    private func entry(pid: pid_t, parent: pid_t) -> ProcessEntry? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              pid_t(info.pbi_ppid) == parent, info.pbi_uid == getuid(),
              let arguments = Self.arguments(of: pid)
        else { return nil }
        return ProcessEntry(pid: pid, parentPID: parent, userID: info.pbi_uid, arguments: arguments)
    }

    private static func arguments(of pid: pid_t) -> [String]? {
        var name: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&name, UInt32(name.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var block = [UInt8](repeating: 0, count: size)
        guard sysctl(&name, UInt32(name.count), &block, &size, nil, 0) == 0 else { return nil }
        return parseArguments(Array(block.prefix(size)))
    }

    /// The kernel's `KERN_PROCARGS2` block: the argument count (`Int32`), the program's path, padding zeros, then that
    /// many zero-terminated arguments, then the environment. nil when the block is shorter than it says.
    nonisolated static func parseArguments(_ block: [UInt8]) -> [String]? {
        guard block.count >= MemoryLayout<Int32>.size else { return nil }
        let argc = block.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc >= 0 else { return nil }
        var index = MemoryLayout<Int32>.size
        // The program's path, then the zeros that pad it.
        while index < block.count, block[index] != 0 { index += 1 }
        while index < block.count, block[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < Int(argc) {
            guard index < block.count, let end = block[index...].firstIndex(of: 0) else { return nil }
            arguments.append(String(decoding: block[index..<end], as: UTF8.self))
            index = end + 1
        }
        return arguments
    }
}
