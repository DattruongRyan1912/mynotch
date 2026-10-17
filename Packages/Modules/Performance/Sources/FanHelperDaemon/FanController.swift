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
/// A forced command can be for one fan or for every fan at once (`FanHelperResult.allFans`). For every fan the helper marks all of
/// them as held before the first write, writes every fan's mode, waits until each reads back, and only then writes every fan's
/// target and waits for those: some firmware applies a mode late, or only once every fan's mode is set, and rewrites a target by
/// itself while a fan is still automatic.
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
    /// Fans that were held when a write went wrong and have been given back since, and until when to keep looking at them: a mode
    /// that the firmware applies after the helper gave up would leave a fan manual with nobody to hold it, so each tick reads the
    /// mode again and gives the fan back once more if it came on.
    private var lateWatch: [Int: Date] = [:]

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

    /// One fan, or every fan for `FanHelperResult.allFans`.
    public func setForced(fan: Int, rpm: Double) -> FanHelperResult { onQueue { command(.forced, fan, rpm) } }

    public func setFloor(fan: Int, rpm: Double) -> FanHelperResult { onQueue { command(.floor, fan, rpm) } }

    /// One fan, or every fan for `FanHelperResult.allFans`.
    public func setAuto(fan: Int) -> FanHelperResult {
        onQueue {
            if fan == FanHelperResult.allFans {
                restoreAll("asked")
                return result(ok: restorePending.isEmpty, fans: [], detail: restorePending.isEmpty ? "" : "some fans could not be restored")
            }
            guard fans.indices.contains(fan) else { return refuse(fan, "no such fan") }
            if fans[fan].mode != .automatic { toAutomatic([fan], "asked") }
            return result(ok: restorePending.isEmpty, fans: [fan])
        }
    }

    /// Whether any fan is held or waits to be given back or looked at: the helper does not leave while this is true.
    public var isHoldingFans: Bool {
        onQueue { fans.contains { $0.mode != .automatic } || !restorePending.isEmpty || !lateWatch.isEmpty }
    }

    // MARK: Time and the system

    /// Once a second, from a timer on `queue`: expires leases, watches the die temperature, retries a restore that failed.
    public func tick() { onQueue { tickOnQueue() } }

    /// On start: a fan that reads manual (a helper that died while holding it) goes back to automatic, unless Macs Fan Control is the
    /// one that holds it.
    public func startUp() {
        onQueue {
            guard !otherToolRunning() else { return }
            let manual = FanSMC.readFans(on: reader).filter { $0.mode == 1 && fans.indices.contains($0.index) }.map(\.index)
            guard !manual.isEmpty else { return }
            for failure in writer.setManual(manual, false).failures { restorePending.insert(failure.fan) }
            for fan in manual { log("fan \(fan) was manual at start; back to automatic") }
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
        let everyFan = kind == .forced && fan == FanHelperResult.allFans
        guard everyFan || fans.indices.contains(fan) else { return refuse(fan, "no such fan") }
        guard rpm.isFinite, rpm >= 0 else { return refuse(fan, "the speed is not a number") }
        guard !otherToolRunning() else { return refuse(fan, "Macs Fan Control is running") }
        guard let temperature = dieTemperature() else {
            restoreAll("the die temperature cannot be read")
            return refuse(fan, "the die temperature cannot be read")
        }
        guardActive = FanSafety.guardNext(active: guardActive, temperature: temperature, trip: Self.guardTrip, release: Self.guardRelease)
        let list = everyFan ? Array(fans.indices) : [fan]
        var notes = list.contains { FanSafety.clamp(rpm, min: fans[$0].minRPM, max: fans[$0].maxRPM) != rpm } ? ["clamped to the fan's range"] : []
        if guardActive {
            notes.append("heat guard")
            holdAtMaximum(list)
            let held = list.filter { fans[$0].mode != .automatic }
            return result(
                ok: held.count == list.count, fans: list, applied: held.map { fans[$0].maxRPM }, detail: notes.joined(separator: ", ")
            )
        }
        switch kind {
        case .forced: return forced(list, rpm, temperature, notes)
        case .floor: return floor(fan, FanSafety.clamp(rpm, min: fans[fan].minRPM, max: fans[fan].maxRPM), notes)
        }
    }

    private func forced(_ list: [Int], _ rpm: Double, _ temperature: Double, _ notes: [String]) -> FanHelperResult {
        let seen = FanSMC.readFans(on: reader)
        var wanted: [Int: Double] = [:]
        var left: [(fan: Int, reason: String)] = []
        for fan in list {
            if fans[fan].mode == .automatic {
                // Apple's own speed, measured while Apple is in control.
                fans[fan].baseline = seen.first { $0.index == fan }?.rpm
                fans[fan].baselineTemperature = temperature
            }
            let asked = FanSafety.clamp(rpm, min: fans[fan].minRPM, max: fans[fan].maxRPM)
            switch FanSafety.forcedDecision(
                requested: asked, baseline: fans[fan].baseline, dieTemperature: temperature,
                baselineTemperature: fans[fan].baselineTemperature, drift: Self.baselineDrift
            ) {
            case let .force(speed): wanted[fan] = speed
            case let .automatic(reason): left.append((fan, reason))
            }
        }
        // For every fan, one that Apple drives faster than the request is held at Apple's own speed rather than left automatic: that
        // is still never below Apple, and it keeps every fan's mode in the set that is written together, which is what a chip
        // that takes a mode only once all of them are set needs.
        if list.count > 1, !wanted.isEmpty {
            for (fan, reason) in left where reason == FanSafety.appleIsHigher {
                if let baseline = fans[fan].baseline {
                    wanted[fan] = FanSafety.clamp(baseline, min: fans[fan].minRPM, max: fans[fan].maxRPM)
                }
            }
            left.removeAll { wanted[$0.fan] != nil }
        }
        for (fan, reason) in left {
            if fans[fan].mode != .automatic { toAutomatic([fan], reason) }
            if reason.hasPrefix("hotter") { fans[fan].baseline = nil }
        }
        let why = list.count == 1 ? left.map(\.reason) : left.map { "fan \($0.fan): \($0.reason)" }
        let detail = (why + notes).joined(separator: ", ")
        guard !wanted.isEmpty else { return result(ok: true, fans: list, detail: detail) }

        // Every fan is marked as held before the first write, so that whatever goes wrong after it, the way back to automatic covers
        // everything that may have been written.
        let plan = wanted.sorted { $0.key < $1.key }
        for (fan, speed) in plan {
            fans[fan].mode = .forced(speed)
            lateWatch[fan] = nil
        }
        // The modes first, all of them and only those that do not already read manual (a renewal writes none), then the targets.
        let needMode = plan.map(\.key).filter { fan in seen.first { $0.index == fan }?.mode != 1 }
        let modes = writer.setManual(needMode, true)
        if let failure = modes.failures.first { return failSafe(failure) }
        let latest = needMode.isEmpty ? seen : FanSMC.readFans(on: reader)
        let needTarget = plan.filter { fan, speed in
            guard let target = latest.first(where: { $0.index == fan })?.target, target >= 0 else { return true }
            return abs(target - speed) > FanKeyWriter.readBackTolerance
        }
        let targets = writer.setTargets(needTarget.map { FanTarget(fan: $0.key, rpm: $0.value) })
        if let failure = targets.failures.first { return failSafe(failure) }
        let until = now().addingTimeInterval(Self.leaseSeconds)
        for (fan, _) in plan { fans[fan].leaseUntil = until }
        return result(ok: true, fans: list, applied: plan.map(\.value), detail: detail, modeMS: modes.readBackMS.values.max() ?? -1)
    }

    private func floor(_ fan: Int, _ target: Double, _ notes: [String]) -> FanHelperResult {
        guard let actual = actualRPM(fan) else { return refuse(fan, "the fan's speed cannot be read") }
        if case .forced = fans[fan].mode {
            // From a held fan back to automatic first; what it is doing now is the least that can be asked.
            if let failure = writer.setManual([fan], false).failures.first { return failSafe(failure) }
            fans[fan].mode = .automatic
            fans[fan].baseline = actual
        } else if fans[fan].mode == .automatic {
            fans[fan].baseline = actual
        }
        let floorRPM = FanSafety.clamp(max(target, fans[fan].baseline ?? actual), min: fans[fan].minRPM, max: fans[fan].maxRPM)
        fans[fan].mode = .floor(floorRPM)
        if let failure = writer.setTargets([FanTarget(fan: fan, rpm: floorRPM)]).failures.first { return failSafe(failure) }
        fans[fan].leaseUntil = now().addingTimeInterval(Self.leaseSeconds)
        return result(ok: true, fans: [fan], applied: [floorRPM], detail: notes.joined(separator: ", "))
    }

    private func tickOnQueue() {
        retryPendingRestores()
        watchForLateModes()
        let current = now()
        let expired = fans.indices.filter { index in
            guard fans[index].mode != .automatic, let until = fans[index].leaseUntil else { return false }
            return current >= until
        }
        toAutomatic(expired, "lease expired")
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
        if guardActive { holdAtMaximum(held) }
    }

    private func retryPendingRestores() {
        guard !restorePending.isEmpty else { return }
        let pending = restorePending.sorted()
        let failed = Dictionary(uniqueKeysWithValues: writer.setManual(pending, false).failures.map { ($0.fan, $0.error) })
        for fan in pending {
            if let error = failed[fan] {
                log("fan \(fan) could not be given back yet: \(error.text)")
            } else {
                restorePending.remove(fan)
            }
        }
    }

    /// A fan that a failed command held, and whose mode reads manual after all (the firmware was late), is given back again.
    private func watchForLateModes() {
        guard !lateWatch.isEmpty else { return }
        let current = now()
        let seen = FanSMC.readFans(on: reader)
        for (fan, until) in lateWatch.sorted(by: { $0.key < $1.key }) {
            if current >= until {
                lateWatch[fan] = nil
            } else if fans[fan].mode == .automatic, !otherToolRunning(), seen.first(where: { $0.index == fan })?.mode == 1 {
                toAutomatic([fan], "its mode came on late")
            }
        }
    }

    /// The heat guard's action on held fans: manual at each one's maximum, every mode before any target. A fan whose mode cannot be
    /// written gets the target alone; one whose target cannot be written goes back to automatic.
    private func holdAtMaximum(_ list: [Int]) {
        let todo = list.filter { fans[$0].mode != .forced(fans[$0].maxRPM) }
        guard !todo.isEmpty else { return }
        let needMode = todo.filter { if case .forced = fans[$0].mode { false } else { true } }
        let modeFailed = Set(writer.setManual(needMode, true).failures.map(\.fan))
        for fan in needMode {
            if modeFailed.contains(fan) {
                log("fan \(fan): the heat guard could not force it")
            } else {
                fans[fan].mode = .forced(fans[fan].maxRPM)
            }
        }
        let targetFailed = Set(writer.setTargets(todo.map { FanTarget(fan: $0, rpm: fans[$0].maxRPM) }).failures.map(\.fan))
        for fan in todo where !targetFailed.contains(fan) {
            if modeFailed.contains(fan) {
                fans[fan].mode = .floor(fans[fan].maxRPM)
            } else {
                fans[fan].mode = .forced(fans[fan].maxRPM)
                fans[fan].leaseUntil = fans[fan].leaseUntil ?? now().addingTimeInterval(Self.leaseSeconds)
                log("fan \(fan) held at the maximum by the heat guard")
            }
        }
        toAutomatic(todo.filter { targetFailed.contains($0) }, "the heat guard could not hold it")
    }

    private func toAutomatic(_ list: [Int], _ reason: String) {
        guard !list.isEmpty else { return }
        for failure in writer.setManual(list, false).failures { restorePending.insert(failure.fan) }
        for fan in list {
            fans[fan].mode = .automatic
            fans[fan].leaseUntil = nil
            log("fan \(fan) back to automatic: \(reason)")
        }
    }

    private func restoreAll(_ reason: String) {
        toAutomatic(fans.indices.filter { fans[$0].mode != .automatic }, reason)
        guardActive = false
        for index in fans.indices { fans[index].baseline = nil }
    }

    private func failSafe(_ failure: FanWriteFailure) -> FanHelperResult {
        log("fan \(failure.fan): \(failure.error.text); every fan back to automatic")
        let held = fans.indices.filter { fans[$0].mode != .automatic }
        restoreAll("an SMC error")
        let until = now().addingTimeInterval(Self.leaseSeconds)
        for fan in held { lateWatch[fan] = until }
        return result(ok: false, fans: [failure.fan], detail: failure.error.text)
    }

    private func actualRPM(_ fan: Int) -> Double? {
        FanSMC.readFans(on: reader).first { $0.index == fan }?.rpm
    }

    private func refuse(_ fan: Int, _ detail: String) -> FanHelperResult {
        let state = fans.indices.contains(fan) ? stateOf(fan) : .automatic
        return FanHelperResult(ok: false, state: state, detail: detail, leaseSeconds: remainingLease(fan))
    }

    /// The answer for the fans a command was about. `applied` is the speeds written (their mean is the one reported, which for one
    /// fan is its own), `modeMS` how long the slowest mode took to read back.
    private func result(ok: Bool, fans list: [Int], applied: [Double] = [], detail: String = "", modeMS: Int = -1) -> FanHelperResult {
        let known = list.filter { fans.indices.contains($0) }
        guard !known.isEmpty else { return FanHelperResult(ok: ok, state: .automatic, detail: detail, modeReadBackMS: modeMS) }
        let states = known.map(stateOf)
        let state: FanHelperResult.State = states.contains(.forced) ? .forced : states.contains(.floor) ? .floor : .automatic
        return FanHelperResult(
            ok: ok, state: state, appliedRPM: applied.isEmpty ? -1 : applied.reduce(0, +) / Double(applied.count), detail: detail,
            leaseSeconds: known.map(remainingLease).max() ?? 0, modeReadBackMS: modeMS
        )
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
