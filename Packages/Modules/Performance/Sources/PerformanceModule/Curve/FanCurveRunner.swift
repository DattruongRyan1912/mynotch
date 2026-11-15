import Foundation
import Observation

/// What keeps the app from being slowed down while the curve runs. App Nap would stretch the timers of an app with no window past the
/// helper's 15-second lease, and the fans would flap between the curve and Apple.
protocol ActivityAssertion {
    func begin()
    func end()
}

final class SystemActivityAssertion: ActivityAssertion {
    private var token: (any NSObjectProtocol)?

    func begin() {
        guard token == nil else { return }
        token = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep], reason: "MyNotch's fan curve")
    }

    func end() {
        if let token { ProcessInfo.processInfo.endActivity(token) }
        token = nil
    }
}

/// Runs the user's curve: each time the temperature is read, asks the engine what each fan should do and tells the helper, which holds
/// it for a lease and renews it at the next read. Only while the curve is the mode, the helper runs, a way of setting the fans is
/// known from the probe, and Macs Fan Control is not running; otherwise the fans are Apple's. It never decides what is safe: the
/// helper clamps, refuses and guards; this decides what is wanted. A helper that stops answering is looked for again on a schedule,
/// so that the curve does not wait for the user to open a tab.
@Observable
final class FanCurveRunner {
    /// How long to wait before each look at a helper that does not answer, counted from the moment it was first missed and then
    /// from the end of the previous look: 5 s, 15 s, 30 s, and `steadyLookDelay` for every one after. None is shorter than 5 s, so
    /// two looks are never closer than that, and a look is awaited before the next wait begins, so there is never more than one.
    static let lookDelays: [TimeInterval] = [5, 15, 30]
    static let steadyLookDelay: TimeInterval = 60

    enum Status: Equatable {
        /// The mode is Apple's.
        case off
        case waitingForHelper
        /// A helper answers, but it is of another version than the one inside this app, so it is not given commands.
        case helperOutdated
        case needsProbe
        case blockedByMacsFanControl
        /// The curve is the mode and working: `rpm` is the average speed the fans were asked for, nil while Apple is still in charge
        /// (below the start temperature, or the helper kept a fan automatic because Apple's own speed was higher).
        case active(rpm: Double?)
        case error(String)
    }

    private(set) var status = Status.off

    @ObservationIgnored private let helper: FanHelperManager
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let activity: any ActivityAssertion
    @ObservationIgnored private var engine = FanCurveEngine()
    @ObservationIgnored private var mode = FanMode.apple
    @ObservationIgnored private var curve = FanCurve.standard
    @ObservationIgnored private var mechanism: FanMechanism?
    /// Whether a command that holds a fan has been sent and not taken back.
    @ObservationIgnored private var holding = false
    /// Whether the app is being kept from App Nap, so that it is begun once and ended once.
    @ObservationIgnored private var isAwake = false
    /// Since when the helper has been waited for without a look (or since the last look ended), and how many looks this absence has had.
    @ObservationIgnored private var waitingSince: Date?
    @ObservationIgnored private var looks = 0

    init(helper: FanHelperManager, now: @escaping () -> Date = { Date() }, activity: any ActivityAssertion = SystemActivityAssertion()) {
        self.helper = helper
        self.now = now
        self.activity = activity
    }

    /// Whether the curve is the mode, which is what makes the module keep reading the temperature.
    var isOn: Bool { mode == .curve }

    /// For the tab, next to the fans: "Đường cong · 3200 vòng/phút". Nil when the curve is not the mode.
    var activeText: String? {
        switch status {
        case .off: nil
        case let .active(rpm?): "Đường cong · \(Int(rpm.rounded())) vòng/phút"
        case .active(nil): "Đường cong · đang để Apple"
        case .waitingForHelper, .helperOutdated, .needsProbe, .blockedByMacsFanControl, .error: "Đường cong · tạm dừng"
        }
    }

    // MARK: Settings

    /// A change of the user's settings. Going back to Apple's mode gives the fans back at once.
    func configure(mode newMode: FanMode, curve newCurve: FanCurve, mechanism newMechanism: FanMechanism?) async {
        let changedMode = newMode != mode
        mode = newMode
        curve = newCurve
        mechanism = newMechanism
        helper.curveIsMode = newMode == .curve
        if changedMode {
            engine.reset()
            forgetLooks()
        }
        switch newMode {
        case .apple:
            await stop()
        case .curve:
            if !isAwake {
                activity.begin()
                isAwake = true
            }
            if case .off = status { status = .waitingForHelper }
        }
    }

    /// Gives the fans back and lets the app be slowed down again; on switching to Apple's mode, on stopping the module, and on the
    /// way out.
    func stop() async {
        if isAwake {
            activity.end()
            isAwake = false
        }
        engine.reset()
        forgetLooks()
        if holding { await helper.giveFansBack() }
        holding = false
        status = .off
    }

    // MARK: Each reading

    func step(_ snapshot: ThermalSnapshot) async {
        guard mode == .curve else { return }
        // A probe is trying the fans: the curve keeps its hands off them until it is done.
        guard helper.probeStep == nil else { return }
        helper.refreshMacsFanControl()
        if case .unreachable = helper.phase {
            await lookAgainWhenDue()
            // A look that finds the helper is acted on at the next reading, with a temperature read after it.
            guard mode == .curve else { return }
            return await pause(.waitingForHelper)
        }
        forgetLooks()
        guard case .running = helper.phase else { return await pause(.waitingForHelper) }
        guard !helper.helperIsOutdated else { return await pause(.helperOutdated) }
        guard let mechanism else { return await pause(.needsProbe) }
        guard !helper.macsFanControlRunning else { return await pause(.blockedByMacsFanControl) }
        guard let temperature = snapshot.soc, !snapshot.fans.isEmpty else {
            return await pause(.error("Không đọc được nhiệt độ hoặc quạt"))
        }
        let fans = snapshot.fans.map { FanLimits(index: $0.index, minRPM: $0.minRPM, maxRPM: $0.maxRPM, currentRPM: $0.rpm) }
        let directives = engine.step(temperature: temperature, at: now(), curve: curve, fans: fans)
        var asked: [Double] = []
        do {
            switch mechanism {
            case .floor:
                for (fan, directive) in zip(fans, directives) {
                    guard case let .rpm(rpm) = directive else { continue }
                    holding = true
                    let result = try await helper.commandClient.setFloor(fan: fan.index, rpm: rpm)
                    guard result.ok else { return await refused(result) }
                    if result.state != .automatic { asked.append(result.appliedRPM ?? rpm) }
                }
            case .forced:
                // One command for every fan, the way the probe found the SMC takes it: the helper sets all the modes and then all the
                // targets. It holds the speed to each fan's own range, so the fastest any fan is asked for is the speed to send: no
                // fan gets less than the curve asks for it.
                let speeds = directives.compactMap { directive -> Double? in
                    if case let .rpm(rpm) = directive { rpm } else { nil }
                }
                if let rpm = speeds.max() {
                    holding = true
                    let result = try await helper.commandClient.setForced(fan: FanCommandResult.allFans, rpm: rpm)
                    guard result.ok else { return await refused(result) }
                    if result.state != .automatic { asked.append(result.appliedRPM ?? rpm) }
                }
            }
        } catch {
            return await pause(.error(FanHelperManager.describe(error)))
        }
        if asked.isEmpty {
            // Nothing is held: below the start, or Apple's own speed is higher everywhere.
            if holding, !directives.contains(where: { if case .rpm = $0 { true } else { false } }) {
                await helper.giveFansBack()
                holding = false
            }
            status = .active(rpm: nil)
        } else {
            status = .active(rpm: asked.reduce(0, +) / Double(asked.count))
        }
    }

    // MARK: Looking for the helper

    /// The helper did not answer the last time anybody looked (the app was replaced under a helper that has not yet left, say, and
    /// its signing check fails): asks the manager to look again when the schedule says so. The readings come every two seconds, so a
    /// look is made at the first reading at or after its time, and the reading that makes it waits for the answer.
    private func lookAgainWhenDue() async {
        let moment = now()
        let since = waitingSince ?? moment
        waitingSince = since
        let delay = looks < Self.lookDelays.count ? Self.lookDelays[looks] : Self.steadyLookDelay
        guard moment.timeIntervalSince(since) >= delay else { return }
        looks += 1
        await helper.lookAgain()
        waitingSince = now()
    }

    /// The helper is there, or the curve is not the mode: the next absence starts its schedule again.
    private func forgetLooks() {
        waitingSince = nil
        looks = 0
    }

    /// The helper's own refusal (Macs Fan Control, a temperature it cannot read, an SMC that did not apply what was written): not the
    /// curve's to argue with.
    private func refused(_ result: FanCommandResult) async {
        await pause(.error(result.detail.isEmpty ? "helper từ chối" : result.detail))
    }

    /// The curve cannot run now, for this reason: the fans go back to Apple if they were held.
    private func pause(_ new: Status) async {
        if holding {
            await helper.giveFansBack()
            holding = false
        }
        engine.reset()
        status = new
    }
}
