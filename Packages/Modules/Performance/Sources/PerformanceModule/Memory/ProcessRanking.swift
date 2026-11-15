import Darwin
import Foundation

/// How to look at the processes of the Mac; the real one is `ProcessSource.live`, tests pass their own.
nonisolated struct ProcessSource: Sendable {
    var pids: @Sendable () -> [Int32]
    /// The physical footprint in bytes; nil for a process that cannot be read (another user's, or the system's).
    var footprint: @Sendable (Int32) -> UInt64?
    /// The name the kernel keeps (cut at 31 characters).
    var name: @Sendable (Int32) -> String?
    var path: @Sendable (Int32) -> String?
}

nonisolated enum ProcessRanking {
    /// The `limit` processes that hold the most memory, heaviest first, ties by process number. Processes that cannot be read are
    /// skipped, as are the kernel's own number (0) and any that hold nothing. Names and paths are looked up for the winners only:
    /// the footprint is asked for every process (a thousand of them), the rest for a handful.
    static func top(_ limit: Int, from source: ProcessSource) -> [ProcessMemory] {
        guard limit > 0 else { return [] }
        let heaviest = source.pids()
            .filter { $0 > 0 }
            .compactMap { pid in source.footprint(pid).flatMap { $0 > 0 ? (pid: pid, footprint: $0) : nil } }
            .sorted { ($0.footprint, $1.pid) > ($1.footprint, $0.pid) }
            .prefix(limit)
        return heaviest.map { entry in
            let path = source.path(entry.pid)
            let name = path.map { ($0 as NSString).lastPathComponent }.flatMap { $0.isEmpty ? nil : $0 }
                ?? source.name(entry.pid)
                ?? "Tiến trình \(entry.pid)"
            return ProcessMemory(pid: entry.pid, name: name, footprint: entry.footprint, path: path)
        }
    }

    /// The app a path is inside: everything up to the first `.app` folder, so a helper deep in an app's bundle gets the app's
    /// icon. Nil for an executable that is not in an app.
    static func appBundlePath(of executablePath: String) -> String? {
        guard let end = executablePath.range(of: ".app/") else { return nil }
        return String(executablePath[..<end.upperBound].dropLast())
    }
}

nonisolated extension ProcessSource {
    static let live = ProcessSource(
        pids: {
            let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
            guard bytes > 0 else { return [] }
            // Room for processes started between the two calls.
            var buffer = [Int32](repeating: 0, count: Int(bytes) / MemoryLayout<Int32>.size + 64)
            let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &buffer, Int32(buffer.count * MemoryLayout<Int32>.size))
            return written > 0 ? Array(buffer.prefix(Int(written) / MemoryLayout<Int32>.size)) : []
        },
        footprint: { pid in
            var info = rusage_info_v4()
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            return status == 0 ? info.ri_phys_footprint : nil
        },
        name: { pid in
            var buffer = [CChar](repeating: 0, count: 64)
            let length = proc_name(pid, &buffer, UInt32(buffer.count))
            return length > 0 ? string(from: buffer, length: Int(length)) : nil
        },
        path: { pid in
            var buffer = [CChar](repeating: 0, count: 4096)   // PROC_PIDPATHINFO_MAXSIZE
            let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
            return length > 0 ? string(from: buffer, length: Int(length)) : nil
        }
    )

    private static func string(from buffer: [CChar], length: Int) -> String {
        String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
