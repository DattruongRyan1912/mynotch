import FanHelperKit
import Foundation

/// Holds the fans for the app, and gives them back. Everything the helper promises is here, so it is the same whoever asks:
///
/// * **Auto by default.** A fan is only ever held because a command said so, for a lease of 15 s; the same command again renews it,
///   and with no renewal the fan goes back to Apple's control by itself. Auto also on start (for a fan that reads manual), on exit,
///   on sleep and wake, on any SMC error, and when asked.
/// * **Clamped.** Every speed is held to the fan's own range (`F<N>Mn` to `F<N>Mx`).
/// * **Never below Apple.** A manual speed below what Apple's control was doing is not set: the fan stays automatic.
/// * **A heat guard** for the fans it holds: at 95 °C the die's hottest sensor sends them to the maximum whatever was asked, and
///   below 90 °C it lets go; if the temperature cannot be read while a fan is held, the fan goes back to automatic.
/// * **Not while Macs Fan Control runs.**
///
/// All state lives on one serial queue. Commands, the tick, signals, power events and the exit path all go through it, and the
/// exit path runs directly when it is already on it, so restoring cannot deadlock itself.
public final class FanController: @unchecked Sendable {
    public static let leaseSeconds: TimeInterval = 15
    public static let guardTrip = 95.0
    public static let guardRelease = 90.0
    public static let baselineDrift = 4.0

    enum Mode: Equatable {
        case automatic
        case floor(Double)
        case forced(Double)
    }

    private struct Fan {
        let minRPM: Double
        let maxRPM: Double
        var mode = Mode.automatic
        var leaseUntil: Date?
        /// Apple's own speed under automatic control, and the die temperature it was read at.
        var baseline: Double?
        var baselineTemperature: Double?
    }

    private enum Kind {
        case floor, forced
    }

    public let queue: DispatchQueue
    private let queueKey = DispatchSpecificKey<Void>()
    private let writer: FanKeyWriter
    private let reader: any SMCChannel
    private let dieTemperature: @Sendable () -> Double?
    private let now: @Sendable () -> Date
    private let otherToolRunning: @Sendable () -> Bool
    private let log: @Sendable (String) -> Void
    private var fans: [Fan]
    private var guardActive = false
    /// Fans whose return to automatic could not be written; retried at every tick.
    private var restorePending: Set<Int> = []

    /// Nil when the limits of the writer's fans cannot be read.
    public init?(
        writer: FanKeyWriter, reader: any SMCChannel, dieTemperature: @escaping @Sendable () -> Double?,
        now: @escaping @Sendable () -> Date = { Date() }, otherToolRunning: @escaping @Sendable () -> Bool = { false },
        log: @escaping @Sendable (String) -> Void = { _ in },
        queue: DispatchQueue = DispatchQueue(label: "io.lucasvu.mynotch.fanhelper.controller")
    ) {
        let read = FanSMC.readFans(on: reader)
        guard read.count >= writer.fanCount else { return nil }
        fans = (0..<writer.fanCount).map { Fan(minRPM: read[$0].minRPM, maxRPM: read[$0].maxRPM) }
        self.writer = writer
        self.reader = reader
        self.dieTemperature = dieTemperature
        self.now = now
        self.otherToolRunning = otherToolRunning
        self.log = log
        self.queue = queue
        queue.setSpecific(key: queueKey, value: ())
    }

    // MARK: Commands

    public func setForced(fan: Int, rpm: Double) -> FanHelperResult { onQueue { command(.forced, fan, rpm) } }

    public func setFloor(fan: Int, rpm: Double) -> FanHelperResult { onQueue { command(.floor, fan, rpm) } }

    /// One fan, or every fan for `FanHelperResult.allFans`.
    public func setAuto(fan: Int) -> FanHelperResult {
        onQueue {
            if fan == FanHelperResult.allFans {
                restoreAll("asked")
                return result(ok: restorePending.isEmpty, fan: nil, detail: restorePending.isEmpty ? "" : "some fans could not be restored")
            }
            guard fans.indices.contains(fan) else { return refuse(fan, "no such fan") }
            if fans[fan].mode != .automatic { toAutomatic(fan, "asked") }
            return result(ok: restorePending.isEmpty, fan: fan)
        }
    }

    /// Whether any fan is held or waits to be given back: the helper does not leave while this is true.
    public var isHoldingFans: Bool {
        onQueue { fans.contains { $0.mode != .automatic } || !restorePending.isEmpty }
    }

    // MARK: Time and the system

    /// Once a second, from a timer on `queue`: expires leases, watches the die temperature, retries a restore that failed.
    public func tick() { onQueue { tickOnQueue() } }

    /// On start: a fan that reads manual (a helper that died while holding it) goes back to automatic, unless Macs Fan Control is the
    /// one that holds it.
    public func startUp() {
        onQueue {
            guard !otherToolRunning() else { return }
            for fan in FanSMC.readFans(on: reader) where fan.mode == 1 && fans.indices.contains(fan.index) {
                do { try writer.setManual(fan.index, false) } catch { restorePending.insert(fan.index) }
                log("fan \(fan.index) was manual at start; back to automatic")
            }
        }
    }

    public func systemWillSleep() { onQueue { restoreAll("sleep") } }
    public func systemDidWake() { onQueue { restoreAll("wake") } }

    /// Before the process ends, whatever the way: gives every fan back to Apple. Runs directly when it is already on the queue (a
    /// signal handler on it, the idle exit) and otherwise waits for the queue for at most `timeout` seconds, so a stuck queue cannot keep
    /// the helper from leaving.
    public func restoreAutoForExit(timeout: TimeInterval = 2) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            restoreAll("exit")
            return
        }
        let done = DispatchSemaphore(value: 0)
        queue.async {
            self.restoreAll("exit")
            done.signal()
        }
        _ = done.wait(timeout: .now() + timeout)
    }

    // MARK: Inside the queue

    private func onQueue<T>(_ body: () -> T) -> T {
        DispatchQueue.getSpecific(key: queueKey) != nil ? body() : queue.sync(execute: body)
    }

    private func command(_ kind: Kind, _ fan: Int, _ rpm: Double) -> FanHelperResult {
        guard fans.indices.contains(fan) else { return refuse(fan, "no such fan") }
        guard rpm.isFinite, rpm >= 0 else { return refuse(fan, "the speed is not a number") }
        guard !otherToolRunning() else { return refuse(fan, "Macs Fan Control is running") }
        guard let temperature = dieTemperature() else {
            restoreAll("the die temperature cannot be read")
            return refuse(fan, "the die temperature cannot be read")
        }
        guardActive = FanSafety.guardNext(active: guardActive, temperature: temperature, trip: Self.guardTrip, release: Self.guardRelease)
        let limits = fans[fan]
        let target = FanSafety.clamp(rpm, min: limits.minRPM, max: limits.maxRPM)
        var notes = target != rpm ? ["clamped to the fan's range"] : []
        if guardActive {
            notes.append("heat guard")
            holdAtMaximum(fan)
            return result(ok: fans[fan].mode != .automatic, fan: fan, detail: notes.joined(separator: ", "))
        }
        switch kind {
        case .forced: return forced(fan, target, temperature, notes)
        case .floor: return floor(fan, target, notes)
        }
    }

    private func forced(_ fan: Int, _ target: Double, _ temperature: Double, _ notes: [String]) -> FanHelperResult {
        if fans[fan].mode == .automatic {
            // Apple's own speed, measured while Apple is in control.
            fans[fan].baseline = actualRPM(fan)
            fans[fan].baselineTemperature = temperature
        }
        let decision = FanSafety.forcedDecision(
            requested: target, baseline: fans[fan].baseline, dieTemperature: temperature,
            baselineTemperature: fans[fan].baselineTemperature, drift: Self.baselineDrift
        )
        switch decision {
        case let .automatic(reason):
            if fans[fan].mode != .automatic { toAutomatic(fan, reason) }
            if reason.hasPrefix("hotter") { fans[fan].baseline = nil }
            return result(ok: true, fan: fan, detail: ([reason] + notes).joined(separator: ", "))
        case let .force(rpm):
            // Marked as held before the first write, so that if the second one fails the way back to automatic covers the first.
            let wasForced: Bool
            if case .forced = fans[fan].mode { wasForced = true } else { wasForced = false }
            fans[fan].mode = .forced(rpm)
            do {
                if !wasForced { try writer.setManual(fan, true) }
                try writer.setTarget(fan, rpm: rpm)
            } catch {
                return failSafe(fan, error)
            }
            fans[fan].leaseUntil = now().addingTimeInterval(Self.leaseSeconds)
            return result(ok: true, fan: fan, applied: rpm, detail: notes.joined(separator: ", "))
        }
    }

    private func floor(_ fan: Int, _ target: Double, _ notes: [String]) -> FanHelperResult {
        guard let actual = actualRPM(fan) else { return refuse(fan, "the fan's speed cannot be read") }
        if case .forced = fans[fan].mode {
            // From a held fan back to automatic first; what it is doing now is the least that can be asked.
            do { try writer.setManual(fan, false) } catch { return failSafe(fan, error) }
            fans[fan].mode = .automatic
            fans[fan].baseline = actual
        } else if fans[fan].mode == .automatic {
            fans[fan].baseline = actual
        }
        let floorRPM = FanSafety.clamp(max(target, fans[fan].baseline ?? actual), min: fans[fan].minRPM, max: fans[fan].maxRPM)
        fans[fan].mode = .floor(floorRPM)
        do { try writer.setTarget(fan, rpm: floorRPM) } catch { return failSafe(fan, error) }
        fans[fan].leaseUntil = now().addingTimeInterval(Self.leaseSeconds)
        return result(ok: true, fan: fan, applied: floorRPM, detail: notes.joined(separator: ", "))
    }

    private func tickOnQueue() {
        for fan in restorePending.sorted() {
            do {
                try writer.setManual(fan, false)
                restorePending.remove(fan)
            } catch {
                log("fan \(fan) could not be given back yet: \(error.text)")
            }
        }
        let current = now()
        for index in fans.indices where fans[index].mode != .automatic {
            if let until = fans[index].leaseUntil, current >= until { toAutomatic(index, "lease expired") }
        }
        let held = fans.indices.filter { fans[$0].mode != .automatic }
        guard !held.isEmpty else {
            guardActive = false
            return
        }
        guard let temperature = dieTemperature() else {
            restoreAll("the die temperature cannot be read")
            return
        }
        guardActive = FanSafety.guardNext(active: guardActive, temperature: temperature, trip: Self.guardTrip, release: Self.guardRelease)
        if guardActive { for index in held { holdAtMaximum(index) } }
    }

    /// The heat guard's action on a held fan: manual at the maximum; if that cannot be written, the target alone; if not that, automatic.
    private func holdAtMaximum(_ fan: Int) {
        let maximum = fans[fan].maxRPM
        if fans[fan].mode == .forced(maximum) { return }
        do {
            if case .forced = fans[fan].mode {} else { try writer.setManual(fan, true) }
            try writer.setTarget(fan, rpm: maximum)
            fans[fan].mode = .forced(maximum)
            fans[fan].leaseUntil = fans[fan].leaseUntil ?? now().addingTimeInterval(Self.leaseSeconds)
            log("fan \(fan) held at the maximum by the heat guard")
            return
        } catch {
            log("fan \(fan): the heat guard could not force it: \(error.text)")
        }
        do {
            try writer.setTarget(fan, rpm: maximum)
            fans[fan].mode = .floor(maximum)
        } catch {
            toAutomatic(fan, "the heat guard could not hold it")
        }
    }

    private func toAutomatic(_ fan: Int, _ reason: String) {
        do { try writer.setManual(fan, false) } catch { restorePending.insert(fan) }
        fans[fan].mode = .automatic
        fans[fan].leaseUntil = nil
        log("fan \(fan) back to automatic: \(reason)")
    }

    private func restoreAll(_ reason: String) {
        for index in fans.indices where fans[index].mode != .automatic { toAutomatic(index, reason) }
        guardActive = false
        for index in fans.indices { fans[index].baseline = nil }
    }

    private func failSafe(_ fan: Int, _ error: FanWriteError) -> FanHelperResult {
        log("fan \(fan): \(error.text); every fan back to automatic")
        restoreAll("an SMC error")
        return result(ok: false, fan: fan, detail: error.text)
    }

    private func actualRPM(_ fan: Int) -> Double? {
        FanSMC.readFans(on: reader).first { $0.index == fan }?.rpm
    }

    private func refuse(_ fan: Int, _ detail: String) -> FanHelperResult {
        let state = fans.indices.contains(fan) ? stateOf(fan) : .automatic
        return FanHelperResult(ok: false, state: state, detail: detail, leaseSeconds: remainingLease(fan))
    }

    private func result(ok: Bool, fan: Int?, applied: Double = -1, detail: String = "") -> FanHelperResult {
        guard let fan, fans.indices.contains(fan) else { return FanHelperResult(ok: ok, state: .automatic, detail: detail) }
        return FanHelperResult(ok: ok, state: stateOf(fan), appliedRPM: applied, detail: detail, leaseSeconds: remainingLease(fan))
    }

    private func stateOf(_ fan: Int) -> FanHelperResult.State {
        switch fans[fan].mode {
        case .automatic: .automatic
        case .floor: .floor
        case .forced: .forced
        }
    }

    private func remainingLease(_ fan: Int) -> Double {
        guard fans.indices.contains(fan), let until = fans[fan].leaseUntil else { return 0 }
        return max(0, until.timeIntervalSince(now()))
    }
}
