import Darwin
import Foundation

/// Single-process reads through libproc and sysctl. Every call is a system call; none of them belongs on the main actor.
nonisolated enum LibprocProcess {
    /// `SZOMB`: exited, waiting to be reaped.
    private static let zombie: UInt32 = 5

    /// The pids whose effective user is `uid`: the system filters, so the processes of other users are never even opened.
    static func pids(ownedBy uid: uid_t) -> [Int32] {
        let size = proc_listpids(UInt32(PROC_UID_ONLY), uid, nil, 0)
        guard size > 0 else { return [] }
        // Processes come and go between the two calls, so there is room for more than the first one counted.
        var pids = [Int32](repeating: 0, count: Int(size) / MemoryLayout<Int32>.size + 64)
        let written = pids.withUnsafeMutableBytes { proc_listpids(UInt32(PROC_UID_ONLY), uid, $0.baseAddress, Int32($0.count)) }
        guard written > 0 else { return [] }
        return pids.prefix(Int(written) / MemoryLayout<Int32>.size).filter { $0 > 0 }
    }

    /// Who the process is now and its short name; nil when there is no such process or it has exited.
    static func info(of pid: Int32) -> (identity: ProcessIdentity, shortName: String)? {
        var bsd = proc_bsdinfo()
        let size = withUnsafeMutableBytes(of: &bsd) { proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, $0.baseAddress, Int32($0.count)) }
        guard size == Int32(MemoryLayout<proc_bsdinfo>.size), bsd.pbi_status != zombie else { return nil }
        let identity = ProcessIdentity(
            pid: pid, uid: bsd.pbi_uid, realUID: bsd.pbi_ruid,
            startTime: bsd.pbi_start_tvsec * 1_000_000 + bsd.pbi_start_tvusec, path: path(of: pid)
        )
        let comm = withUnsafeBytes(of: bsd.pbi_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return (identity, comm)
    }

    static func path(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cChars: buffer)
    }

    /// The arguments as a short line; nil when the system keeps them from us (it does for its own protected processes).
    static func commandLine(of pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size + 1024)
        size = buffer.count
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return ProcArguments.display(ProcArguments.parse(Array(buffer.prefix(size))))
    }
}
