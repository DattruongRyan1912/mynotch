import FanHelperKit
import Foundation

public enum FanWriteError: Error, Equatable, Sendable {
    case noSuchFan
    case notAFiniteSpeed
    case missingKey(String)
    case wrongType(String)
    case refused(String, UInt8)
    case failed(String, Int32)
    case readBackDiffers(String)

    /// A short English line for the log and for the reply.
    public var text: String {
        switch self {
        case .noSuchFan: "no such fan"
        case .notAFiniteSpeed: "the speed is not a number"
        case let .missingKey(key): "the SMC has no \(key)"
        case let .wrongType(key): "\(key) is not of the expected type"
        case let .refused(key, code): "the SMC refused \(key) (0x\(String(code, radix: 16)))"
        case let .failed(key, code): "writing \(key) failed (\(code))"
        case let .readBackDiffers(key): "\(key) does not read back as written"
        }
    }
}

/// What the writer reads the time from and waits with, so that a test runs a second of waiting instantly.
public struct FanWriteTiming: Sendable {
    /// Seconds on a clock that only goes forward.
    public var now: @Sendable () -> TimeInterval
    public var sleep: @Sendable (TimeInterval) -> Void

    public init(now: @escaping @Sendable () -> TimeInterval, sleep: @escaping @Sendable (TimeInterval) -> Void) {
        self.now = now
        self.sleep = sleep
    }

    public static let live = FanWriteTiming(now: { ProcessInfo.processInfo.systemUptime }, sleep: { Thread.sleep(forTimeInterval: $0) })
}

/// A target speed for one fan.
public struct FanTarget: Equatable, Sendable {
    public let fan: Int
    public let rpm: Double

    public init(fan: Int, rpm: Double) {
        self.fan = fan
        self.rpm = rpm
    }
}

/// A fan whose write did not work, and why.
public struct FanWriteFailure: Equatable, Sendable {
    public let fan: Int
    public let error: FanWriteError
}

/// What a batch of writes came to.
public struct FanWriteReport: Equatable, Sendable {
    public internal(set) var failures: [FanWriteFailure] = []
    /// How long each fan's key took to read back as written, in milliseconds; a fan that failed has none.
    public internal(set) var readBackMS: [Int: Int] = [:]

    public var isOK: Bool { failures.isEmpty }
}

/// Writes the two keys that set a fan, and nothing else: the mode (`F<N>Md`, or `F<N>md` on chips that spell it so) as a `ui8 `, and the
/// target (`F<N>Tg`) as a little-endian `flt `. The key names are made from a fan index that is below the number of fans the SMC
/// reports, the types are checked against what the SMC says each key is, and a speed that is not a number is refused.
///
/// A write that the SMC answers with success is not yet a write that took: the firmware may apply it a moment later, or only once the
/// other fans' modes are set too. So a batch writes every key once, in the order given (a key that fails does not stop the others,
/// so a restore reaches every fan), and then reads all the keys that were accepted every 50 ms for up to a second until each reads
/// back as written; a key that never does is an error, and nothing is written twice. A write that the SMC answers with an error is
/// looked at once instead (the firmware sometimes applies one anyway). Each key gets one log line with the key, the value written,
/// how long it took and what the reads said, and nothing else.
public struct FanKeyWriter: Sendable {
    public static let mostFans = 8
    /// How far a target may read back from what was written: floats of this size are not exact.
    static let readBackTolerance = 1.0
    /// How often a key that was written is read, and for how long, before it counts as never having been applied.
    public static let pollInterval: TimeInterval = 0.05
    public static let readBackBudget: TimeInterval = 1
    /// A clock is read to the millisecond: a read that would fall that close to the end of the budget is not worth another wait.
    static let clockTolerance: TimeInterval = 0.001

    public let fanCount: Int
    private let channel: any SMCWriteChannel
    private let modeKeys: [String]
    private let log: @Sendable (String) -> Void
    private let timing: FanWriteTiming

    /// The only key names this type writes, as a test pins them.
    public static func isAllowedKey(_ key: String) -> Bool {
        let bytes = Array(key.utf8)
        guard bytes.count == 4, bytes[0] == UInt8(ascii: "F"), (0x30...0x37).contains(bytes[1]) else { return false }
        let suffix = String(decoding: bytes[2...], as: UTF8.self)
        return suffix == "Md" || suffix == "md" || suffix == "Tg"
    }

    /// Looks the fans and their mode keys up. Throws when the SMC has no fans or a fan has no mode key of the right type.
    public init(
        channel: any SMCWriteChannel, log: @escaping @Sendable (String) -> Void = { _ in }, timing: FanWriteTiming = .live
    ) throws(FanWriteError) {
        self.channel = channel
        self.log = log
        self.timing = timing
        guard let countInfo = channel.info(of: "FNum"), let countBytes = channel.bytes(of: "FNum", info: countInfo),
              let count = SMCValue.number(type: countInfo.type, bytes: countBytes), count >= 1
        else { throw .missingKey("FNum") }
        fanCount = min(Int(count), Self.mostFans)
        var keys: [String] = []
        for index in 0..<fanCount {
            guard let key = ["F\(index)Md", "F\(index)md"].first(where: { channel.info(of: $0) != nil }),
                  channel.info(of: key)?.type == "ui8 ", channel.info(of: key)?.size == 1
            else { throw .missingKey("F\(index)Md") }
            guard let target = channel.info(of: "F\(index)Tg") else { throw .missingKey("F\(index)Tg") }
            guard target.type == "flt ", target.size == 4 else { throw .wrongType("F\(index)Tg") }
            keys.append(key)
        }
        modeKeys = keys
    }

    // MARK: Batches

    /// 1 for manual, 0 for the system's own control, on every fan of `fans`: all the modes are written first and then all of them
    /// are waited for together, because on some chips a mode only takes once every fan's mode is set.
    public func setManual(_ fans: [Int], _ manual: Bool) -> FanWriteReport {
        guard let failure = invalid(fans) else {
            let value: UInt8 = manual ? 1 : 0
            return write(fans.map { fan in
                Item(fan: fan, key: modeKeys[fan], label: "\(modeKeys[fan])=\(value)", bytes: [value], matches: { $0 == [value] }, reading: { $0.first.map(Int.init) ?? -1 })
            })
        }
        return FanWriteReport(failures: [failure])
    }

    /// Writes every target and waits for all of them together.
    public func setTargets(_ targets: [FanTarget]) -> FanWriteReport {
        if let failure = invalid(targets.map(\.fan)) { return FanWriteReport(failures: [failure]) }
        if let bad = targets.first(where: { !$0.rpm.isFinite || $0.rpm < 0 }) {
            return FanWriteReport(failures: [FanWriteFailure(fan: bad.fan, error: .notAFiniteSpeed)])
        }
        return write(targets.map { target in
            let bits = Float(target.rpm).bitPattern
            let bytes = [UInt8(bits & 0xff), UInt8(bits >> 8 & 0xff), UInt8(bits >> 16 & 0xff), UInt8(bits >> 24 & 0xff)]
            let key = "F\(target.fan)Tg"
            return Item(
                fan: target.fan, key: key, label: "\(key)=\(Int(target.rpm.rounded()))", bytes: bytes,
                matches: { SMCValue.number(type: "flt ", bytes: $0).map { abs($0 - target.rpm) <= Self.readBackTolerance } ?? false },
                reading: { SMCValue.number(type: "flt ", bytes: $0).map { Int($0.rounded()) } ?? -1 }
            )
        })
    }

    // MARK: One fan

    public func setManual(_ fan: Int, _ manual: Bool) throws(FanWriteError) {
        if let failure = setManual([fan], manual).failures.first { throw failure.error }
    }

    public func setTarget(_ fan: Int, rpm: Double) throws(FanWriteError) {
        if let failure = setTargets([FanTarget(fan: fan, rpm: rpm)]).failures.first { throw failure.error }
    }

    // MARK: Writing and waiting

    private struct Item {
        let fan: Int
        let key: String
        let label: String
        let bytes: [UInt8]
        let matches: ([UInt8]) -> Bool
        /// A number for the log out of what was read.
        let reading: ([UInt8]) -> Int
    }

    private struct Waiting {
        let item: Item
        let info: SMCKeyInfo
        let started: TimeInterval
        var readings: [Int] = []
    }

    private func invalid(_ fans: [Int]) -> FanWriteFailure? {
        fans.first { !(0..<fanCount).contains($0) }.map { FanWriteFailure(fan: $0, error: .noSuchFan) }
    }

    private func write(_ items: [Item]) -> FanWriteReport {
        var report = FanWriteReport()
        var waiting: [Waiting] = []
        for item in items {
            precondition(Self.isAllowedKey(item.key), "not a key this type may write")
            guard let info = channel.info(of: item.key), info.size == item.bytes.count else {
                report.failures.append(FanWriteFailure(fan: item.fan, error: .wrongType(item.key)))
                continue
            }
            let started = timing.now()
            switch channel.write(item.key, info: info, bytes: item.bytes) {
            case .ok:
                waiting.append(Waiting(item: item, info: info, started: started))
            case let .smcError(code):
                if let failure = lookOnce(item, info, answered: "result \(code)", error: .refused(item.key, code), report: &report) {
                    report.failures.append(failure)
                }
            case let .ioError(code):
                if let failure = lookOnce(item, info, answered: "code \(code)", error: .failed(item.key, code), report: &report) {
                    report.failures.append(failure)
                }
            }
        }
        awaitReadBack(&waiting, into: &report)
        return report
    }

    /// A write that the SMC answered with an error: the firmware sometimes applies it anyway, so one read decides.
    private func lookOnce(_ item: Item, _ info: SMCKeyInfo, answered: String, error: FanWriteError, report: inout FanWriteReport) -> FanWriteFailure? {
        let read = channel.bytes(of: item.key, info: info)
        guard let read, item.matches(read) else {
            log("\(item.label) \(answered) and reads \(read.map(item.reading) ?? -1)")
            return FanWriteFailure(fan: item.fan, error: error)
        }
        log("\(item.label) read back after 0 ms (\(item.reading(read))), though the SMC answered \(answered)")
        report.readBackMS[item.fan] = 0
        return nil
    }

    /// Reads every key still open each `pollInterval`, until each has read back as written or has had its `readBackBudget`. The
    /// first read comes at once; a key is given up on when no further read would fit in its budget.
    private func awaitReadBack(_ waiting: inout [Waiting], into report: inout FanWriteReport) {
        while !waiting.isEmpty {
            var stillOpen: [Waiting] = []
            for var key in waiting {
                let read = channel.bytes(of: key.item.key, info: key.info)
                key.readings.append(read.map(key.item.reading) ?? -1)
                let elapsed = timing.now() - key.started
                if let read, key.item.matches(read) {
                    let ms = Int((elapsed * 1000).rounded())
                    log("\(key.item.label) read back after \(ms) ms (\(Self.describe(key.readings)))")
                    report.readBackMS[key.item.fan] = ms
                } else if elapsed + Self.pollInterval >= Self.readBackBudget - Self.clockTolerance {
                    log("\(key.item.label) never read back in \(Int(Self.readBackBudget * 1000)) ms (\(Self.describe(key.readings)))")
                    report.failures.append(FanWriteFailure(fan: key.item.fan, error: .readBackDiffers(key.item.key)))
                } else {
                    stillOpen.append(key)
                }
            }
            waiting = stillOpen
            if !waiting.isEmpty { timing.sleep(Self.pollInterval) }
        }
    }

    /// The readings in order, a run of four or more of the same one as `value×count`: `0,0,0,1` or `0×20`.
    static func describe(_ readings: [Int]) -> String {
        var parts: [String] = []
        var start = 0
        while start < readings.count {
            var end = start
            while end + 1 < readings.count, readings[end + 1] == readings[start] { end += 1 }
            let count = end - start + 1
            if count >= 4 {
                parts.append("\(readings[start])×\(count)")
            } else {
                parts += Array(repeating: "\(readings[start])", count: count)
            }
            start = end + 1
        }
        return parts.joined(separator: ",")
    }
}
