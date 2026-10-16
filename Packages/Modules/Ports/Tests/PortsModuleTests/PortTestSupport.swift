import Foundation
import Synchronization
@testable import PortsModule

/// The 16 bytes of libproc's address union for an IPv4 address (in the last four) and for an IPv6 one.
nonisolated enum Bytes {
    static func v4(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> [UInt8] { [UInt8](repeating: 0, count: 12) + [a, b, c, d] }
    static func v6(_ groups: [UInt16]) -> [UInt8] { groups.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xff)] } }
    static let v6Loopback = v6([0, 0, 0, 0, 0, 0, 0, 1])
    static let v6Any = [UInt8](repeating: 0, count: 16)
}

extension PortAddress {
    static let loopback4 = PortAddress(vflag: PortAddress.v4Flag, bytes: Bytes.v4(127, 0, 0, 1))!
    static let loopback6 = PortAddress(vflag: PortAddress.v6Flag, bytes: Bytes.v6Loopback)!
    static let any4 = PortAddress(vflag: PortAddress.v4Flag, bytes: Bytes.v4(0, 0, 0, 0))!
    static let any6 = PortAddress(vflag: PortAddress.v6Flag, bytes: Bytes.v6Any)!
    static let lan = PortAddress(vflag: PortAddress.v4Flag, bytes: Bytes.v4(192, 168, 1, 20))!
}

extension ProcessIdentity {
    static func make(
        pid: Int32 = 4821, uid: UInt32 = 501, realUID: UInt32? = nil, startTime: UInt64 = 1_000, path: String? = "/opt/homebrew/bin/node"
    ) -> ProcessIdentity {
        ProcessIdentity(pid: pid, uid: uid, realUID: realUID ?? uid, startTime: startTime, path: path)
    }
}

extension PortProcess {
    static func make(
        pid: Int32 = 4821, name: String = "node", command: String? = "node server.js", uid: UInt32 = 501, startTime: UInt64 = 1_000,
        path: String? = "/opt/homebrew/bin/node"
    ) -> PortProcess {
        PortProcess(identity: .make(pid: pid, uid: uid, startTime: startTime, path: path), name: name, commandLine: command)
    }
}

extension PortEntry {
    static func make(
        port: UInt16 = 3000, proto: PortProtocol = .tcp, process: PortProcess = .make(), addresses: [PortAddress] = [.loopback4]
    ) -> PortEntry {
        PortEntry(port: port, proto: proto, process: process, addresses: addresses)
    }
}

/// A source whose answer a test sets. Reads happen off the main actor, so the state sits behind a lock.
nonisolated final class FakePortSource: PortSource {
    private struct State {
        var snapshot: PortSnapshot
        var reads = 0
    }

    private let state: Mutex<State>

    init(_ entries: [PortEntry] = []) {
        state = Mutex(State(snapshot: Self.snapshot(of: entries)))
    }

    var reads: Int { state.withLock { $0.reads } }

    func set(_ entries: [PortEntry]) {
        state.withLock { $0.snapshot = Self.snapshot(of: entries) }
    }

    func read() -> PortSnapshot {
        state.withLock {
            $0.reads += 1
            return $0.snapshot
        }
    }

    private static func snapshot(of entries: [PortEntry]) -> PortSnapshot {
        var snapshot = PortSnapshot()
        for entry in entries {
            snapshot.processes[entry.pid] = entry.process
            snapshot.sockets += entry.addresses.map { ListeningSocket(pid: entry.pid, port: entry.port, proto: entry.proto, address: $0) }
        }
        return snapshot
    }
}

/// A process table that signals are sent to instead of the system: what is alive, and what got which signal.
nonisolated final class FakeProcessControl: ProcessControl {
    private struct State {
        var alive: [Int32: ProcessIdentity] = [:]
        var sent: [(signal: StopSignal, pid: Int32)] = []
        /// Signals a process ignores, like a server that traps SIGTERM.
        var ignoring: [Int32: [StopSignal]] = [:]
        var result: SignalResult = .sent
    }

    private let state = Mutex(State())

    init(_ identities: [ProcessIdentity] = []) {
        state.withLock { for identity in identities { $0.alive[identity.pid] = identity } }
    }

    var sent: [(signal: StopSignal, pid: Int32)] { state.withLock { $0.sent } }
    var signals: [StopSignal] { sent.map(\.signal) }

    func add(_ identity: ProcessIdentity) { state.withLock { $0.alive[identity.pid] = identity } }
    func remove(_ pid: Int32) { state.withLock { $0.alive[pid] = nil } }
    func ignore(_ signal: StopSignal, pid: Int32) { state.withLock { $0.ignoring[pid, default: []].append(signal) } }
    func answer(_ result: SignalResult) { state.withLock { $0.result = result } }

    func identity(of pid: Int32) -> ProcessIdentity? { state.withLock { $0.alive[pid] } }

    func send(_ signal: StopSignal, to pid: Int32) -> SignalResult {
        state.withLock {
            $0.sent.append((signal, pid))
            guard $0.alive[pid] != nil else { return .gone }
            if $0.result == .sent, !($0.ignoring[pid] ?? []).contains(signal) { $0.alive[pid] = nil }
            return $0.result
        }
    }
}

nonisolated final class FakePortProbe: PortProbe {
    private let state = Mutex((results: [UInt16: PortProbeResult](), asked: [UInt16]()))

    var asked: [UInt16] { state.withLock { $0.asked } }
    func set(_ result: PortProbeResult, for port: UInt16) { state.withLock { $0.results[port] = result } }

    func probe(port: UInt16) -> PortProbeResult {
        state.withLock {
            $0.asked.append(port)
            return $0.results[port] ?? .free
        }
    }
}
