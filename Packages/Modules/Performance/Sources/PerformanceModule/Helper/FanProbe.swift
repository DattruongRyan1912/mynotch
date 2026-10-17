import Foundation

/// The two ways a fan can be asked for more than Apple gives, as the helper offers them.
nonisolated enum FanMechanism: String, Codable, Equatable, Sendable {
    /// The speed goes to the target key and Apple's automatic mode stays on.
    case floor
    /// The fan is taken to manual mode at the speed.
    case forced
}

/// What one way of setting the fan did in the probe.
nonisolated struct MechanismTrial: Codable, Equatable, Sendable {
    let mechanism: FanMechanism
    /// The helper did what was asked (the fan was in the state asked for, not turned back to automatic or refused).
    let accepted: Bool
    /// The helper's reason when it did not, or any note it made.
    let detail: String
    let baselineRPM: Double
    let requestedRPM: Double
    /// The highest actual speed seen while the command was held: fans spin up gradually.
    let peakRPM: Double
    /// Whether the actual speed went most of the way to the speed asked for.
    let changed: Bool
    /// Whether the SMC kept what was asked for the whole time it was held: the target reading back as written (and for the manual
    /// speed the mode reading 1). A firmware that rewrites the target by itself is fighting the request, not honouring it.
    let heldAsAsked: Bool
    let modeAfter: Double?
    let targetAfter: Double?
    let rpmAfter: Double?
    /// Whether giving the fan back worked: the mode reads automatic and the speed is on its way down, or the target was taken back.
    let restored: Bool

    /// Only a way that changed the speed, kept what was asked for while it was held, and was given back cleanly is a way to use.
    var usable: Bool { accepted && changed && heldAsAsked && restored }
}

/// What the probe found, kept to choose the way the curve sets the fans.
nonisolated struct FanProbeOutcome: Codable, Equatable, Sendable {
    enum Verdict: String, Codable, Equatable, Sendable {
        case notRun
        /// Apple's control stays and a floor works: the way to use.
        case floor
        case forced
        /// Neither way both changed the speed and gave the fan back.
        case none
        /// The fans were too near their maximum to see a change; to be tried again with the Mac cool.
        case inconclusive
    }

    var verdict: Verdict
    var trials: [MechanismTrial]
    var note: String
    var at: Date?

    static let never = FanProbeOutcome(verdict: .notRun, trials: [], note: "", at: nil)

    /// The way the curve sets a fan: the floor when it works (Apple's control stays on, so nothing goes stale), else the manual speed.
    var mechanism: FanMechanism? {
        switch verdict {
        case .floor: .floor
        case .forced: .forced
        case .notRun, .none, .inconclusive: nil
        }
    }
}

/// The probe's arithmetic, apart from the probe so each rule can be tried by itself.
nonisolated enum FanProbeJudge {
    /// Least rise worth judging by: below it the Mac's own speed, fan noise and rounding blur the change.
    static let minimumRise = 800.0
    /// How far towards the requested speed the fan must get to count as changed.
    static let changedFraction = 0.4
    /// How far the target may read back from what was written: the SMC's floats are not exact.
    static let targetTolerance = 100.0

    /// What to ask for: 1500 rpm above the baseline or 60 % of the fan's maximum, whichever is more, never above the maximum. Nil when
    /// that is less than `minimumRise` above the baseline (a fan already near its maximum shows nothing).
    static func requestedRPM(baseline: Double, maximum: Double) -> Double? {
        let wanted = min(max(baseline + 1500, 0.6 * maximum), maximum)
        return wanted - baseline >= minimumRise ? wanted : nil
    }

    static func changed(baseline: Double, requested: Double, peak: Double) -> Bool {
        peak >= baseline + changedFraction * (requested - baseline)
    }

    /// Given back: the mode reads automatic, and either the firmware took the target back or the speed is on its way down.
    static func restored(modeAfter: Double?, targetAfter: Double?, rpmAfter: Double?, requested: Double, peak: Double, baseline: Double) -> Bool {
        guard modeAfter == 0 else { return false }
        if let targetAfter, abs(targetAfter - requested) > 100 { return true }
        if let rpmAfter { return rpmAfter <= peak - 0.25 * (peak - baseline) }
        return false
    }

    /// The way to use: the floor if it passed, else the manual speed, else none.
    static func verdict(for trials: [MechanismTrial]) -> FanProbeOutcome.Verdict {
        if trials.first(where: { $0.mechanism == .floor })?.usable == true { return .floor }
        if trials.first(where: { $0.mechanism == .forced })?.usable == true { return .forced }
        return .none
    }
}

/// The ten-second probe of how the fans can be set, over the helper's own commands. For one fan: reads the baseline, tries the floor
/// for 3 s, gives the fan back and looks at it for 2 s, then the same with the manual speed. Whatever happens, every fan is given back
/// at the end, and the helper's own lease and heat guard stay on throughout.
struct FanControlProbe {
    static let holdSeconds = 3
    static let settleSeconds = 2

    /// How long to wait before looking for the baseline a second time: a helper that is still starting may not have answered.
    static let baselineRetryPause = Duration.seconds(1)

    let client: any FanHelperClient
    let pause: (Duration) async -> Void
    let now: () -> Date
    /// Hears a line for the log; never a value, only what went wrong.
    let log: (String) -> Void
    var fan = 0

    init(
        client: any FanHelperClient, fan: Int = 0, pause: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        now: @escaping () -> Date = { Date() }, log: @escaping (String) -> Void = { _ in }
    ) {
        self.client = client
        self.fan = fan
        self.pause = pause
        self.now = now
        self.log = log
    }

    /// `step` hears "what is happening now" for the progress line.
    func run(step: (String) -> Void = { _ in }) async -> FanProbeOutcome {
        let outcome = await sequence(step: step)
        // Whatever the sequence did, every fan goes back to Apple.
        _ = try? await client.setAuto(fan: FanCommandResult.allFans)
        return outcome
    }

    private func sequence(step: (String) -> Void) async -> FanProbeOutcome {
        step("Đọc tốc độ quạt hiện tại")
        let baseline: FanHelperFanInfo
        switch await readBaseline() {
        case let .success(found): baseline = found
        case let .failure(failure):
            return FanProbeOutcome(verdict: .inconclusive, trials: [], note: failure.note, at: now())
        }
        guard let requested = FanProbeJudge.requestedRPM(baseline: baseline.rpm, maximum: baseline.maxRPM) else {
            return FanProbeOutcome(
                verdict: .inconclusive, trials: [],
                note: "Quạt đang chạy gần tốc độ tối đa (\(Int(baseline.rpm)) trên \(Int(baseline.maxRPM))), không thấy được thay đổi. Thử lại khi máy nguội.",
                at: now()
            )
        }
        var trials: [MechanismTrial] = []
        for mechanism in [FanMechanism.floor, .forced] {
            guard !Task.isCancelled else { break }
            step(mechanism == .floor ? "Thử đặt sàn tốc độ" : "Thử đặt tốc độ thủ công")
            trials.append(await trial(mechanism, baseline: baseline, requested: requested))
            _ = try? await client.setAuto(fan: FanCommandResult.allFans)
        }
        let verdict = trials.count == 2 ? FanProbeJudge.verdict(for: trials) : .inconclusive
        return FanProbeOutcome(verdict: verdict, trials: trials, note: trials.count == 2 ? "" : "Đã dừng giữa chừng.", at: now())
    }

    /// Why the baseline could not be had.
    enum BaselineFailure: Error, Equatable {
        /// The call to the helper failed; the reason in words.
        case threw(String)
        /// The helper answered with no fans at all.
        case noFans
        /// The helper answered with fans, none of them the one being probed.
        case noSuchFan

        var note: String {
            switch self {
            case let .threw(reason): "Helper không đọc được quạt: \(reason)."
            case .noFans: "Helper không thấy quạt nào."
            case .noSuchFan: "Helper không có quạt được thử."
            }
        }

        /// The line for the log: what happened and nothing measured.
        var logLine: String {
            switch self {
            case let .threw(reason): "probe baseline: readFans failed (\(reason))"
            case .noFans: "probe baseline: readFans returned no fans"
            case .noSuchFan: "probe baseline: readFans has no fan with the probed index"
            }
        }
    }

    /// The fan's reading before anything is set. A helper that was not running has to be started by the first call and may answer
    /// late or not at all, so the read is tried twice, a second apart; each failure is logged with its reason.
    private func readBaseline() async -> Result<FanHelperFanInfo, BaselineFailure> {
        var last = BaselineFailure.noFans
        for attempt in 0..<2 {
            if attempt > 0 { await pause(Self.baselineRetryPause) }
            switch await attemptBaseline() {
            case let .success(found): return .success(found)
            case let .failure(failure):
                last = failure
                log(failure.logLine + (attempt == 0 ? "; trying again" : ""))
            }
        }
        return .failure(last)
    }

    private func attemptBaseline() async -> Result<FanHelperFanInfo, BaselineFailure> {
        do {
            let fans = try await client.readFans()
            guard !fans.isEmpty else { return .failure(.noFans) }
            guard let found = fans.first(where: { $0.index == fan }) else { return .failure(.noSuchFan) }
            return .success(found)
        } catch {
            return .failure(.threw(FanHelperManager.describe(error)))
        }
    }

    /// A reading taken while a command is held shows what was asked for: the target as written, and for the manual speed the mode 1.
    static func holds(_ sample: FanHelperFanInfo, mechanism: FanMechanism, requested: Double) -> Bool {
        guard abs(sample.target - requested) <= FanProbeJudge.targetTolerance else { return false }
        return mechanism == .floor || sample.mode == 1
    }

    private func trial(_ mechanism: FanMechanism, baseline: FanHelperFanInfo, requested: Double) async -> MechanismTrial {
        var accepted = true
        var detail = ""
        var peak = baseline.rpm
        var heldAsAsked = true
        for _ in 0..<Self.holdSeconds {
            do {
                let result = mechanism == .floor
                    ? try await client.setFloor(fan: fan, rpm: requested) : try await client.setForced(fan: fan, rpm: requested)
                let expected: FanCommandResult.State = mechanism == .floor ? .floor : .forced
                if !result.ok || result.state != expected {
                    accepted = false
                    detail = result.detail
                }
            } catch {
                accepted = false
                detail = FanHelperManager.describe(error)
            }
            await pause(.seconds(1))
            if let sample = try? await client.readFans().first(where: { $0.index == fan }) {
                peak = max(peak, sample.rpm)
                if !Self.holds(sample, mechanism: mechanism, requested: requested) { heldAsAsked = false }
            } else {
                heldAsAsked = false
            }
            if !accepted { break }
        }
        _ = try? await client.setAuto(fan: fan)
        await pause(.seconds(Self.settleSeconds))
        let after = try? await client.readFans().first { $0.index == fan }
        let modeAfter = after.map(\.mode)
        let targetAfter = after.map(\.target)
        let rpmAfter = after.map(\.rpm)
        return MechanismTrial(
            mechanism: mechanism, accepted: accepted, detail: detail, baselineRPM: baseline.rpm, requestedRPM: requested, peakRPM: peak,
            changed: FanProbeJudge.changed(baseline: baseline.rpm, requested: requested, peak: peak), heldAsAsked: heldAsAsked,
            modeAfter: modeAfter, targetAfter: targetAfter, rpmAfter: rpmAfter,
            restored: FanProbeJudge.restored(
                modeAfter: modeAfter, targetAfter: targetAfter, rpmAfter: rpmAfter, requested: requested, peak: peak, baseline: baseline.rpm
            )
        )
    }
}
