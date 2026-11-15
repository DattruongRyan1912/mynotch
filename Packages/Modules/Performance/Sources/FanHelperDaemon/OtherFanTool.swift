import Darwin
import Foundation

/// Whether the Macs Fan Control app is running, which the helper never fights: its helper daemon runs all the time and says
/// nothing about it, so it is the app's process that is looked for. A scan of the process list is cached for a second.
public final class OtherFanTool: @unchecked Sendable {
    /// The part of an executable's path that is that app's.
    public static let appExecutableMarker = "/Macs Fan Control.app/Contents/MacOS/"

    private let paths: @Sendable () -> [String]
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var cached: (at: Date, running: Bool)?

    public init(paths: @escaping @Sendable () -> [String] = OtherFanTool.livePaths, now: @escaping @Sendable () -> Date = { Date() }) {
        self.paths = paths
        self.now = now
    }

    public func isRunning() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let current = now()
        if let cached, current.timeIntervalSince(cached.at) < 1 { return cached.running }
        let running = paths().contains { $0.contains(Self.appExecutableMarker) }
        cached = (current, running)
        return running
    }

    /// The executable paths of every process the helper may look at.
    public static func livePaths() -> [String] {
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(bytes) / MemoryLayout<Int32>.size + 64)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard written > 0 else { return [] }
        var paths: [String] = []
        var buffer = [CChar](repeating: 0, count: 4096)
        for pid in pids.prefix(Int(written) / MemoryLayout<Int32>.size) where pid > 0 {
            let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
            if length > 0 { paths.append(String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)) }
        }
        return paths
    }
}
