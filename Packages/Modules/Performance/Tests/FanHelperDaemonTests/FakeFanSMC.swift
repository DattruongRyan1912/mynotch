import FanHelperKit
import Foundation
import Synchronization
@testable import FanHelperDaemon

/// An SMC in memory with this Mac's fan keys. It records every write, can refuse a key, and never touches the real one. With a clock
/// it can also behave the ways a real firmware may: apply a mode a while after the write, never apply it, apply the modes only once
/// every fan's has been written, and rewrite a target by itself while a fan is automatic.
final class FakeFanSMC: SMCWriteChannel, Sendable {
    struct Write: Equatable {
        let key: String
        let bytes: [UInt8]
    }

    private struct Pending {
        let due: TimeInterval
        let key: String
        let bytes: [UInt8]
    }

    private struct State {
        var entries: [String: (type: String, bytes: [UInt8], attributes: UInt8)]
        var writes: [Write] = []
        /// What a write to this key answers; the bytes are still applied when `appliesAnyway` is set for it.
        var refusals: [String: UInt8] = [:]
        var byteRefusals: [String: (bytes: [UInt8], code: UInt8)] = [:]
        var appliesAnyway: Set<String> = []
        /// Writes that were accepted and will be applied at a time, in the order they were written.
        var pending: [Pending] = []
        /// Seconds between a write of "manual" to a mode key and the SMC applying it.
        var modeOnDelay: TimeInterval = 0
        /// Keys whose writes are acknowledged and ignored.
        var neverApplied: Set<String> = []
        /// Modes take only once every fan's has been written "manual"; until then they are held.
        var modesNeedEveryFan = false
        var modeOnWritten: Set<Int> = []
        var held: [Pending] = []
        /// While a fan's mode (as applied) is automatic, its target reads as the firmware's own: the speed it is actually at.
        var firmwareOwnsTargetWhileAutomatic = false
    }

    private let state: Mutex<State>
    private let clock: @Sendable () -> TimeInterval
    private let fans: Int

    init(fans: Int = 2, actual: Double = 2000, clock: @escaping @Sendable () -> TimeInterval = { 0 }) {
        var entries: [String: (type: String, bytes: [UInt8], attributes: UInt8)] = ["FNum": ("ui8 ", [UInt8(fans)], 0)]
        let maxima = [5779.0, 6241.0, 6000.0, 6000.0]
        for index in 0..<fans {
            entries["F\(index)Ac"] = ("flt ", Self.float(actual), 0)
            entries["F\(index)Mn"] = ("flt ", Self.float(1200), 0)
            entries["F\(index)Mx"] = ("flt ", Self.float(maxima[index % maxima.count]), 0)
            entries["F\(index)Md"] = ("ui8 ", [0], 0)
            entries["F\(index)Tg"] = ("flt ", Self.float(actual), 0)
        }
        state = Mutex(State(entries: entries))
        self.clock = clock
        self.fans = fans
    }

    static func float(_ value: Double) -> [UInt8] {
        let bits = Float(value).bitPattern
        return [UInt8(bits & 0xff), UInt8(bits >> 8 & 0xff), UInt8(bits >> 16 & 0xff), UInt8(bits >> 24 & 0xff)]
    }

    // MARK: What a test sets up and reads

    var writes: [Write] { state.withLock { $0.writes } }
    func clearWrites() { state.withLock { $0.writes = [] } }
    func setActual(_ rpm: Double, fan: Int) { state.withLock { $0.entries["F\(fan)Ac"] = ("flt ", Self.float(rpm), 0) } }
    func setMode(_ mode: UInt8, fan: Int) { state.withLock { $0.entries["F\(fan)Md"] = ("ui8 ", [mode], 0) } }
    func remove(_ key: String) { state.withLock { $0.entries[key] = nil } }
    func replace(_ key: String, type: String, bytes: [UInt8], attributes: UInt8 = 0) { state.withLock { $0.entries[key] = (type, bytes, attributes) } }
    func refuse(_ key: String, code: UInt8 = 0x82, appliesAnyway: Bool = false) {
        state.withLock {
            $0.refusals[key] = code
            if appliesAnyway { $0.appliesAnyway.insert(key) }
        }
    }
    func refuseIf(_ key: String, bytes: [UInt8], code: UInt8 = 0x82) {
        state.withLock {
            $0.byteRefusals[key] = (bytes, code)
        }
    }
    func allow(_ key: String) { state.withLock { $0.refusals[key] = nil } }

    /// The firmware applies "manual" this long after the write (writes of "automatic" are at once).
    func applyModeOn(after seconds: TimeInterval) { state.withLock { $0.modeOnDelay = seconds } }
    /// The firmware acknowledges writes to these keys and ignores them.
    func neverApply(_ keys: String...) { state.withLock { $0.neverApplied.formUnion(keys) } }
    func modesStickOnlyWhenEveryFanIsSet() { state.withLock { $0.modesNeedEveryFan = true } }
    func firmwareRewritesTheTargetWhileAutomatic() { state.withLock { $0.firmwareOwnsTargetWhileAutomatic = true } }

    func mode(fan: Int) -> UInt8? { read("F\(fan)Md")?.first }
    func target(fan: Int) -> Double? { read("F\(fan)Tg").flatMap { SMCValue.number(type: "flt ", bytes: $0) } }

    // MARK: SMCWriteChannel

    func keyName(at index: Int) -> String? { nil }

    func info(of key: String) -> SMCKeyInfo? {
        state.withLock { $0.entries[key] }.map { SMCKeyInfo(size: $0.bytes.count, type: $0.type, attributes: $0.attributes) }
    }

    func bytes(of key: String, info: SMCKeyInfo) -> [UInt8]? { read(key) }

    func write(_ key: String, info: SMCKeyInfo, bytes: [UInt8]) -> SMCWriteResult {
        let current = clock()
        return state.withLock { state in
            state.writes.append(Write(key: key, bytes: bytes))
            if let refusal = state.byteRefusals[key], bytes == refusal.bytes {
                return .smcError(refusal.code)
            }
            if let code = state.refusals[key] {
                if state.appliesAnyway.contains(key) { state.entries[key]?.bytes = bytes }
                return .smcError(code)
            }
            if state.neverApplied.contains(key) { return .ok }
            if let fan = Self.fan(ofModeKey: key) {
                if bytes == [1] {
                    state.modeOnWritten.insert(fan)
                    let write = Pending(due: current + state.modeOnDelay, key: key, bytes: bytes)
                    if state.modesNeedEveryFan, state.modeOnWritten.count < fans {
                        state.held.append(write)
                    } else {
                        state.pending.append(contentsOf: state.held + [write])
                        state.held = []
                    }
                    return .ok
                }
                state.modeOnWritten.remove(fan)
                state.held.removeAll { $0.key == key }
            }
            state.entries[key]?.bytes = bytes
            return .ok
        }
    }

    private static func fan(ofModeKey key: String) -> Int? {
        let bytes = Array(key.utf8)
        guard bytes.count == 4, bytes[0] == UInt8(ascii: "F"), bytes[2] == UInt8(ascii: "M") || bytes[2] == UInt8(ascii: "m"), bytes[3] == UInt8(ascii: "d")
        else { return nil }
        return Int(bytes[1]) - 0x30
    }

    /// What a read says now: writes that were due have been applied, in the order they were written.
    private func read(_ key: String) -> [UInt8]? {
        let current = clock()
        return state.withLock { state in
            // A clock far from zero adds rounding to every sum: a millisecond is the precision that counts.
            let due = state.pending.filter { $0.due <= current + 0.0005 }
            state.pending.removeAll { $0.due <= current + 0.0005 }
            for write in due { state.entries[write.key]?.bytes = write.bytes }
            if state.firmwareOwnsTargetWhileAutomatic, key.hasSuffix("Tg"), let fan = Int(String(key.dropFirst().prefix(1))),
               state.entries["F\(fan)Md"]?.bytes.first == 0 {
                return state.entries["F\(fan)Ac"]?.bytes
            }
            return state.entries[key]?.bytes
        }
    }
}

/// A clock a test moves.
final class FakeClock: Sendable {
    private let current = Mutex(Date(timeIntervalSinceReferenceDate: 10_000))
    var date: Date { current.withLock { $0 } }
    var seconds: TimeInterval { date.timeIntervalSinceReferenceDate }
    func advance(_ seconds: TimeInterval) { current.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

/// The waits the writer asked for.
final class SleepLog: Sendable {
    private let all = Mutex<[TimeInterval]>([])
    func add(_ seconds: TimeInterval) { all.withLock { $0.append(seconds) } }
    var durations: [TimeInterval] { all.withLock { $0 } }
}

extension FanWriteTiming {
    /// Waiting moves the test's clock, so that a second of waiting costs nothing and the SMC fake sees the time pass.
    static func fake(_ clock: FakeClock, sleeps: SleepLog = SleepLog()) -> FanWriteTiming {
        FanWriteTiming(now: { clock.seconds }, sleep: { seconds in
            sleeps.add(seconds)
            clock.advance(seconds)
        })
    }
}

/// A value that a test changes while the controller reads it from its queue.
final class Box<Value: Sendable>: Sendable {
    private let value: Mutex<Value>
    init(_ value: Value) { self.value = Mutex(value) }
    var current: Value {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}

final class LogLines: Sendable {
    private let lines = Mutex<[String]>([])
    func add(_ line: String) { lines.withLock { $0.append(line) } }
    var all: [String] { lines.withLock { $0 } }
}

/// A controller over a fake SMC with a clock, a temperature and an "other tool" flag in the test's hands.
struct Rig {
    let smc: FakeFanSMC
    let clock = FakeClock()
    let sleeps = SleepLog()
    let temperature: Box<Double?>
    let otherTool = Box(false)
    let logs = LogLines()
    let controller: FanController

    /// `configure` sets up how the fake firmware behaves before the controller exists.
    init(fans: Int = 2, actual: Double = 2000, temperature: Double? = 60, configure: (FakeFanSMC) -> Void = { _ in }) {
        let clock = self.clock
        let smc = FakeFanSMC(fans: fans, actual: actual, clock: { clock.seconds })
        configure(smc)
        let temp = Box<Double?>(temperature)
        let other = otherTool
        let logs = self.logs
        self.smc = smc
        self.temperature = temp
        let writer = try! FanKeyWriter(channel: smc, log: { logs.add($0) }, timing: .fake(clock, sleeps: sleeps))
        controller = FanController(
            writer: writer, reader: smc, dieTemperature: { temp.current }, now: { clock.date },
            otherToolRunning: { other.current }, log: { logs.add($0) }
        )!
    }

    var writes: [FakeFanSMC.Write] { smc.writes }
}

extension FakeFanSMC.Write {
    static func mode(_ fan: Int, _ value: UInt8) -> Self { Self(key: "F\(fan)Md", bytes: [value]) }
    static func target(_ fan: Int, _ rpm: Double) -> Self { Self(key: "F\(fan)Tg", bytes: FakeFanSMC.float(rpm)) }
}
