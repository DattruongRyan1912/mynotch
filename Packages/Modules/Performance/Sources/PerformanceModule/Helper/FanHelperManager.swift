import FanHelperKit
import Foundation
import Observation
import os

/// Installs, checks and removes the fan helper, and says where it is. It acts only when the user presses a button, with one
/// exception: when the app starts and the helper is already installed and running but is not the one inside this app (the app was
/// replaced), it registers it again, once. Nothing here is faked into doing more than reading: the helper itself can only ping and
/// read.
@Observable
final class FanHelperManager {
    static let macsFanControlBundleID = "com.crystalidea.macsfancontrol"
    /// How long to wait between the system stopping the old helper and registering again: reports from developers say registering
    /// at once can fail with "Operation not permitted".
    static let reRegisterPause = Duration.seconds(1)
    static let stillOutdated = "helper cũ vẫn đang chạy. Bấm Gỡ helper rồi Cài lại, hoặc đăng xuất rồi đăng nhập lại"

    private(set) var phase: FanHelperPhase = .unknown
    private(set) var macsFanControlRunning = false
    private(set) var comparison: FanComparison?

    @ObservationIgnored private let registration: any FanHelperRegistering
    @ObservationIgnored private let client: any FanHelperClient
    @ObservationIgnored private let bundled: () -> BundledFanHelper
    @ObservationIgnored private let runningApps: () -> Set<String>
    @ObservationIgnored private let pause: (Duration) async -> Void
    @ObservationIgnored private let log = Logger(subsystem: "io.lucasvu.mynotch", category: "fan-helper")
    @ObservationIgnored private var didTryUpdate = false

    init(
        registration: any FanHelperRegistering,
        client: any FanHelperClient,
        bundled: @escaping () -> BundledFanHelper,
        runningApps: @escaping () -> Set<String>,
        pause: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.registration = registration
        self.client = client
        self.bundled = bundled
        self.runningApps = runningApps
        self.pause = pause
    }

    var isBusy: Bool {
        if case .busy = phase { return true }
        return false
    }

    var presentation: FanHelperPresentation {
        FanHelperPresentation(phase: phase, macsFanControlRunning: macsFanControlRunning)
    }

    // MARK: What the user presses

    /// "Cài helper điều khiển quạt".
    func install() async {
        guard !isBusy else { return }
        set(.busy(.installing))
        do {
            try registration.register()
        } catch {
            // Already registered is as good as registered, and so is waiting for approval; the status tells which.
            log.notice("register threw: \(String(describing: error), privacy: .public)")
            if registration.status == .notRegistered || registration.status == .notFound {
                set(.failed(Self.describe(error)))
                return
            }
        }
        await settleAfterChange()
    }

    /// "Gỡ helper".
    func uninstall() async {
        guard !isBusy else { return }
        set(.busy(.removing))
        comparison = nil
        do {
            try await registration.unregister()
        } catch {
            log.notice("unregister threw: \(String(describing: error), privacy: .public)")
            set(.failed(Self.describe(error)))
            return
        }
        await settleAfterChange()
    }

    /// "Mở Cài đặt": the user allows the helper themselves.
    func openSystemSettings() {
        registration.openSystemSettings()
    }

    /// "Thử lại": registers again when the status says it is not, otherwise looks again.
    func retry() async {
        if registration.status == .notRegistered { await install() } else { await settleAfterChange() }
    }

    // MARK: What the app does by itself

    /// Looks at the registration and, when the helper is enabled and not known to be running, asks it who it is. Never registers.
    /// Called when the tab or Settings appears; it does nothing while an install or removal is under way.
    func refresh() async {
        refreshMacsFanControl()
        guard !isBusy else { return }
        if case .running = phase, registration.status == .enabled { return }
        await readState()
    }

    /// Once as the app starts: an installed helper that is not the one in this app is registered again. Does nothing for a helper
    /// that was never installed, one waiting for approval, or one that does not answer, and tries at most once per launch.
    func checkAtLaunch() async {
        refreshMacsFanControl()
        guard !isBusy else { return }
        await readState()
        let status = registration.status
        var running: FanHelperInfo?
        if case let .running(info) = phase { running = info }
        let bundled = bundled()
        guard FanHelperUpdatePolicy.decide(status: status, running: running, bundled: bundled, alreadyTried: didTryUpdate) == .reRegister
        else { return }
        didTryUpdate = true
        log.notice("the running helper is not the bundled one; registering it again")
        await reRegister(bundled: bundled)
    }

    /// Reads the fans through the helper and sets them beside what the app read itself.
    func compareFans(app: [FanReading]) async {
        guard case .running = phase else { return }
        do {
            comparison = FanComparison(helper: try await client.readFans(), app: app)
        } catch {
            comparison = FanComparison(failure: Self.describe(error))
            if case .running = phase { set(.unreachable(Self.describe(error))) }
        }
    }

    func refreshMacsFanControl() {
        macsFanControlRunning = runningApps().contains(Self.macsFanControlBundleID)
    }

    // MARK: Steps

    private func reRegister(bundled: BundledFanHelper) async {
        set(.busy(.updating))
        do {
            try await registration.unregister()
        } catch {
            set(.failed(Self.describe(error)))
            return
        }
        await pause(Self.reRegisterPause)
        do {
            try registration.register()
        } catch {
            log.notice("register after update threw: \(String(describing: error), privacy: .public)")
            if registration.status == .notRegistered || registration.status == .notFound {
                set(.failed(Self.describe(error)))
                return
            }
        }
        await readState()
        if case let .running(info) = phase, FanHelperUpdatePolicy.isOutdated(info, bundled: bundled) {
            set(.failed(Self.stillOutdated))
        }
    }

    private func settleAfterChange() async {
        await readState()
    }

    /// The phase that the registration status says, and for an enabled helper what a ping says.
    private func readState() async {
        switch registration.status {
        case .notRegistered: set(.notInstalled)
        case .requiresApproval: set(.needsApproval)
        case .notFound: set(.notFound)
        case .enabled: await ping()
        }
    }

    private func ping() async {
        do {
            let info = try await client.ping()
            set(info.euid == 0 ? .running(info) : .failed("helper không chạy với quyền root (euid \(info.euid))"))
        } catch {
            set(.unreachable(Self.describe(error)))
        }
    }

    private func set(_ new: FanHelperPhase) {
        guard new != phase else { return }
        log.info("helper: \(String(describing: new), privacy: .public)")
        phase = new
    }

    /// A short Vietnamese reason for an error; the details are in the log.
    static func describe(_ error: any Error) -> String {
        switch error as? FanHelperError {
        case .timeout: return "helper không trả lời"
        case .noProxy: return "không mở được kết nối"
        case let .helperFailed(reason): return "helper báo: \(reason)"
        case nil:
            let nsError = error as NSError
            return nsError.domain == NSCocoaErrorDomain && (nsError.code == 4097 || nsError.code == 4099)
                ? "không có helper nào trả lời" : "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
        }
    }
}
