import Foundation
import Synchronization
@testable import FanHelperKit
@testable import PerformanceModule

/// What this Mac's SMC returned in the TH0 probe, for the keys the module cares about and a few look-alikes, in the order the
/// SMC lists them: key, type, bytes in hex. The temperatures were taken under heavy load (the hottest CPU key reads 80.4).
nonisolated enum ThisMacSMC {
    static let entries: [(key: String, type: String, hex: String)] = [
        ("#KEY", "ui32", "00000803"),
        ("F0Ac", "flt ", "9d71a345"),
        ("F0Md", "ui8 ", "00"),
        ("F0Mn", "flt ", "00009644"),
        ("F0Mx", "flt ", "0098b445"),
        ("F0Tg", "flt ", "0098a345"),
        ("F1Ac", "flt ", "95c1b045"),
        ("F1Md", "ui8 ", "00"),
        ("F1Mn", "flt ", "00009644"),
        ("F1Mx", "flt ", "0008c345"),
        ("F1Tg", "flt ", "00a8b045"),
        ("FNum", "ui8 ", "02"),
        ("TB0T", "flt ", "64661442"),
        ("TCMb", "flt ", "35fe9342"),
        ("TCMz", "flt ", "cbc1a042"),
        ("TG0H", "ioft", "0000250000000000"),
        ("TPD0", "flt ", "20855542"),
        ("TVMD", "flt ", "00000000"),
        ("Ta00", "flt ", "00000000"),
        ("Ta05", "flt ", "d9ce0741"),
        ("Te00", "flt ", "d38d7242"),
        ("Te01", "flt ", "35fe9342"),
        ("Te02", "flt ", "71cd9f42"),
        ("Tg04", "flt ", "a3bc6b42"),
        ("Tg05", "flt ", "b8448842"),
        ("Tg0C", "flt ", "15866f42"),
        ("Tg0D", "flt ", "71298a42"),
        ("Tm02", "flt ", "00a07042"),
        ("Tp00", "flt ", "cd7d7d42"),
        ("Tp01", "flt ", "dabc9042"),
        ("Tp02", "flt ", "2bef9d42"),
        ("Tp04", "flt ", "adeb7442"),
        ("Tp05", "flt ", "106a8c42"),
        ("Tp06", "flt ", "50359942"),
        ("Tp08", "flt ", "98367342"),
        ("Tp09", "flt ", "08908b42"),
        ("Tp0A", "flt ", "94f89342"),
        ("Tp0C", "flt ", "4c486f42"),
        ("Tp0D", "flt ", "f3f08942"),
        ("Tp0E", "flt ", "0acf9542"),
        ("Tp0G", "flt ", "662d6f42"),
        ("Tp0H", "flt ", "ecca8942"),
        ("Tp0I", "flt ", "5e8a9342"),
        ("Tp0K", "flt ", "502b7542"),
        ("Tp0L", "flt ", "40448c42"),
        ("Tp0M", "flt ", "876ea042"),
        ("Tp0O", "flt ", "b27e7642"),
        ("Tp0P", "flt ", "96098d42"),
        ("Tp0Q", "flt ", "cbc1a042"),
        ("Tp0S", "flt ", "c7226e42"),
        ("Tp0T", "flt ", "9f308942"),
        ("Tp0U", "flt ", "cbe19242"),
        ("Tp0W", "flt ", "39e56e42"),
        ("Tp0X", "flt ", "484f8942"),
        ("Tp0Y", "flt ", "ea569b42"),
        ("Tp0a", "flt ", "28556f42"),
        ("Tp0b", "flt ", "f2a48942"),
        ("Tp0c", "flt ", "e7db9442"),
    ]

    static let hottestCPU = 80.37850189208984     // Tp0Q
    static let hottestGPU = 69.08094024658203     // Tg0D
    static let cpuKeyCount = 33
    static let gpuKeyCount = 4
}

/// An in-memory SMC. Counts what it is asked, so a test can see what a read costs.
nonisolated final class FakeSMCChannel: SMCChannel {
    struct Counts: Equatable {
        var keyNames = 0
        var infos = 0
        var reads = 0
    }

    private struct Entry {
        var type: String
        var bytes: [UInt8]
    }

    private let order: [String]
    var allKeys: [String] { order }
    private let entries: Mutex<[String: Entry]>
    let counts = Mutex(Counts())

    init(_ entries: [(key: String, type: String, hex: String)] = ThisMacSMC.entries) {
        order = entries.map(\.key)
        var table = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, Entry(type: $0.type, bytes: Self.bytes(hex: $0.hex))) })
        // `#KEY` counts the keys this fake lists, not the 2051 of the real SMC.
        let count = UInt32(entries.count)
        table["#KEY"] = Entry(type: "ui32", bytes: [UInt8(count >> 24), UInt8(count >> 16 & 0xff), UInt8(count >> 8 & 0xff), UInt8(count & 0xff)])
        self.entries = Mutex(table)
    }

    static func bytes(hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map {
            let start = hex.index(hex.startIndex, offsetBy: $0)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
    }

    /// Little-endian float bytes, as the SMC returns them.
    static func float(_ value: Float) -> [UInt8] {
        let bits = value.bitPattern
        return [UInt8(bits & 0xff), UInt8(bits >> 8 & 0xff), UInt8(bits >> 16 & 0xff), UInt8(bits >> 24 & 0xff)]
    }

    func set(_ key: String, float value: Float) {
        entries.withLock { $0[key]?.bytes = Self.float(value) }
    }

    func set(_ key: String, bytes: [UInt8]) {
        entries.withLock { $0[key]?.bytes = bytes }
    }

    func remove(_ key: String) {
        entries.withLock { $0[key] = nil }
    }

    func keyName(at index: Int) -> String? {
        counts.withLock { $0.keyNames += 1 }
        return order.indices.contains(index) ? order[index] : nil
    }

    func info(of key: String) -> SMCKeyInfo? {
        counts.withLock { $0.infos += 1 }
        return entries.withLock { $0[key] }.map { SMCKeyInfo(size: $0.bytes.count, type: $0.type) }
    }

    func bytes(of key: String, info: SMCKeyInfo) -> [UInt8]? {
        counts.withLock { $0.reads += 1 }
        return entries.withLock { $0[key] }?.bytes
    }
}

/// How often something happened, from any thread.
nonisolated final class OpenCount: Sendable {
    private let count = Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}
