import FanHelperKit
import Foundation
import Synchronization
@testable import FanHelperDaemon

/// An SMC in memory with this Mac's fan keys. It records every write, can refuse a key, and never touches the real one.
final class FakeFanSMC: SMCWriteChannel, Sendable {
    struct Write: Equatable {
        let key: String
        let bytes: [UInt8]
    }

    private struct State {
        var entries: [String: (type: String, bytes: [UInt8])]
        var writes: [Write] = []
        /// What a write to this key answers; the bytes are still applied when `appliesAnyway` is set for it.
        var refusals: [String: UInt8] = [:]
        var appliesAnyway: Set<String> = []
    }

    private let state: Mutex<State>

    init(fans: Int = 2, actual: Double = 2000) {
        var entries: [String: (type: String, bytes: [UInt8])] = ["FNum": ("ui8 ", [UInt8(fans)])]
        let maxima = [5779.0, 6241.0, 6000.0, 6000.0]
        for index in 0..<fans {
            entries["F\(index)Ac"] = ("flt ", Self.float(actual))
            entries["F\(index)Mn"] = ("flt ", Self.float(1200))
            entries["F\(index)Mx"] = ("flt ", Self.float(maxima[index % maxima.count]))
            entries["F\(index)Md"] = ("ui8 ", [0])
            entries["F\(index)Tg"] = ("flt ", Self.float(actual))
        }
        state = Mutex(State(entries: entries))
    }

    static func float(_ value: Double) -> [UInt8] {
        let bits = Float(value).bitPattern
        return [UInt8(bits & 0xff), UInt8(bits >> 8 & 0xff), UInt8(bits >> 16 & 0xff), UInt8(bits >> 24 & 0xff)]
    }

    // MARK: What a test sets up and reads

    var writes: [Write] { state.withLock { $0.writes } }
    func clearWrites() { state.withLock { $0.writes = [] } }
    func setActual(_ rpm: Double, fan: Int) { state.withLock { $0.entries["F\(fan)Ac"] = ("flt ", Self.float(rpm)) } }
    func setMode(_ mode: UInt8, fan: Int) { state.withLock { $0.entries["F\(fan)Md"] = ("ui8 ", [mode]) } }
    func remove(_ key: String) { state.withLock { $0.entries[key] = nil } }
    func replace(_ key: String, type: String, bytes: [UInt8]) { state.withLock { $0.entries[key] = (type, bytes) } }
    func refuse(_ key: String, code: UInt8 = 0x82, appliesAnyway: Bool = false) {
        state.withLock {
            $0.refusals[key] = code
            if appliesAnyway { $0.appliesAnyway.insert(key) }
        }
    }
    func allow(_ key: String) { state.withLock { $0.refusals[key] = nil } }
    func mode(fan: Int) -> UInt8? { state.withLock { $0.entries["F\(fan)Md"]?.bytes.first } }
    func target(fan: Int) -> Double? {
        state.withLock { $0.entries["F\(fan)Tg"] }.flatMap { SMCValue.number(type: $0.type, bytes: $0.bytes) }
    }

    // MARK: SMCWriteChannel

    func keyName(at index: Int) -> String? { nil }

    func info(of key: String) -> SMCKeyInfo? {
        state.withLock { $0.entries[key] }.map { SMCKeyInfo(size: $0.bytes.count, type: $0.type) }
    }

    func bytes(of key: String, info: SMCKeyInfo) -> [UInt8]? { state.withLock { $0.entries[key]?.bytes } }

    func write(_ key: String, info: SMCKeyInfo, bytes: [UInt8]) -> SMCWriteResult {
        state.withLock { state in
            state.writes.append(Write(key: key, bytes: bytes))
            if let code = state.refusals[key] {
                if state.appliesAnyway.contains(key) { state.entries[key]?.bytes = bytes }
                return .smcError(code)
            }
            state.entries[key]?.bytes = bytes
            return .ok
        }
    }
}

/// A clock a test moves.
final class FakeClock: Sendable {
    private let current = Mutex(Date(timeIntervalSinceReferenceDate: 10_000))
    var date: Date { current.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { current.withLock { $0 = $0.addingTimeInterval(seconds) } }
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
    let temperature: Box<Double?>
    let otherTool = Box(false)
    let logs = LogLines()
    let controller: FanController

    init(fans: Int = 2, actual: Double = 2000, temperature: Double? = 60) {
        let smc = FakeFanSMC(fans: fans, actual: actual)
        let clock = self.clock
        let temp = Box<Double?>(temperature)
        let other = otherTool
        let logs = self.logs
        self.smc = smc
        self.temperature = temp
        let writer = try! FanKeyWriter(channel: smc, log: { logs.add($0) })
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
