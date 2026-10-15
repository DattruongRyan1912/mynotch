import Darwin
import Foundation

/// One process as the search for an agent's terminal needs it.
nonisolated struct ProcessEntry: Equatable, Sendable {
    var pid: pid_t
    var parentPID: pid_t
    /// The device name of its controlling terminal, such as `ttys003`; nil when it has none.
    var tty: String?
    var executablePath: String?
}

/// The process table, one process at a time. Behind a protocol so tests walk a table written by hand.
nonisolated protocol ProcessTable: Sendable {
    func entry(pid: pid_t) -> ProcessEntry?
}

/// The real table, through libproc: no process is signalled, started or changed, and what belongs to another user and
/// cannot be read is simply not there.
nonisolated struct SystemProcessTable: ProcessTable {
    func entry(pid: pid_t) -> ProcessEntry? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return ProcessEntry(pid: pid, parentPID: pid_t(info.pbi_ppid), tty: Self.ttyName(of: info), executablePath: Self.path(of: pid))
    }

    private static func ttyName(of info: proc_bsdinfo) -> String? {
        let device = dev_t(bitPattern: info.e_tdev)
        guard device != -1, let name = devname(device, mode_t(S_IFCHR)) else { return nil }
        return String(decoding: UnsafeBufferPointer(start: name, count: strlen(name)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func path(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
