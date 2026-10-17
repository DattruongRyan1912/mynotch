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
/// helper clamps, refuses and guards; this decides what is wanted.
@Observable
final class FanCurveRunner {
    enum Status: Equatable {
        /// The mode is Apple's.
        case off
        case waitingForHelper
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
        case .waitingForHelper, .needsProbe, .blockedByMacsFanControl, .error: "Đường cong · tạm dừng"
        }
    }

    // MARK: Settings

    /// A change of the user's settings. Going back to Apple's mode gives the fans back at once.
    func configure(mode newMode: FanMode, curve newCurve: FanCurve, mechanism newMechanism: FanMechanism?) async {
        let changedMode = newMode != mode
        mode = newMode
        curve = newCurve
        mechanism = newMechanism
        if changedMode { engine.reset() }
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
        if holding { await helper.giveFansBack() }
        holding = false
        status = .off
    }

    // MARK: Each reading

    func step(_ snapshot: ThermalSnapshot) async {
        guard mode == .curve else { return }
        helper.refreshMacsFanControl()
        guard case .running = helper.phase else { return await pause(.waitingForHelper) }
        guard let mechanism else { return await pause(.needsProbe) }
        guard !helper.macsFanControlRunning else { return await pause(.blockedByMacsFanControl) }
        guard let temperature = snapshot.soc, !snapshot.fans.isEmpty else {
            return await pause(.error("Không đọc được nhiệt độ hoặc quạt"))
        }
        let fans = snapshot.fans.map { FanLimits(index: $0.index, minRPM: $0.minRPM, maxRPM: $0.maxRPM, currentRPM: $0.rpm) }
        let directives = engine.step(temperature: temperature, at: now(), curve: curve, fans: fans)
        var asked: [Double] = []
        for (fan, directive) in zip(fans, directives) {
            guard case let .rpm(rpm) = directive else { continue }
            holding = true
            do {
                let result = switch mechanism {
                case .floor: try await helper.commandClient.setFloor(fan: fan.index, rpm: rpm)
                case .forced: try await helper.commandClient.setForced(fan: fan.index, rpm: rpm)
                }
                guard result.ok else {
                    // The helper's own refusal (Macs Fan Control, a temperature it cannot read): not the curve's to argue with.
                    return await pause(.error(result.detail.isEmpty ? "helper từ chối" : result.detail))
                }
                if result.state != .automatic { asked.append(result.appliedRPM ?? rpm) }
            } catch {
                return await pause(.error(FanHelperManager.describe(error)))
            }
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
