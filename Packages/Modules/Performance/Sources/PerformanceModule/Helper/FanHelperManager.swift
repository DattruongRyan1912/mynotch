import FanHelperKit
import Foundation
import Observation
import ServiceManagement
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
    /// What the probe is doing, nil when it is not running. Settable so that a test can stand for a probe in progress.
    var probeStep: String?
    /// Whether the user's curve is the fan mode, told by the curve's runner: the probe and the curve would fight over the same fan.
    var curveIsMode = false

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

    /// What the curve and the probe send their commands through.
    var commandClient: any FanHelperClient { client }

    var isBusy: Bool {
        if case .busy = phase { return true }
        return false
    }

    /// Whether the probe may be started: the helper runs, Macs Fan Control does not, the fans are Apple's (the curve is off), and
    /// nothing else is going on.
    var canProbe: Bool {
        guard case .running = phase else { return false }
        return !macsFanControlRunning && !curveIsMode && probeStep == nil
    }

    var presentation: FanHelperPresentation {
        FanHelperPresentation(phase: phase, macsFanControlRunning: macsFanControlRunning)
    }

    // MARK: What the user presses

    /// "Cài helper điều khiển quạt". The only place an error about the helper's registration is born: until `register()` has thrown,
    /// a daemon that macOS calls not found is just not installed.
    func install() async {
        guard !isBusy else { return }
        set(.busy(.installing))
        do {
            try registration.register()
        } catch {
            log.notice("register threw: \(String(describing: error), privacy: .public)")
            switch Self.outcome(of: error) {
            case .denied:
                // The daemon waits for an administrator to allow it in System Settings: the header says register() throws that.
                set(.needsApproval)
                return
            case .alreadyRegistered:
                break
            case .notPermitted:
                // The status moves to "requires approval" a moment after the throw; an error only if it never does.
                await waitForApprovalToShow()
                if registration.status == .notRegistered || registration.status == .notFound {
                    set(.failed(Self.describe(error)))
                    return
                }
            case .other:
                // Waiting for approval or enabled is as good as registered, and the status tells which.
                if registration.status == .notRegistered || registration.status == .notFound {
                    set(.failed(Self.describe(error)))
                    return
                }
            }
        }
        await readState()
        if phase == .notInstalled { set(.failed(Self.notAccepted)) }
    }

    /// Gives every fan back to Apple, if the helper is there to do it. Never throws: it is what is done on the way out.
    func giveFansBack() async {
        if case .running = phase { _ = try? await client.setAuto(fan: FanCommandResult.allFans) }
    }

    /// The ten-second probe of how the fans can be set. Only while the helper runs and Macs Fan Control does not; nil when not allowed.
    func runProbe() async -> FanProbeOutcome? {
        refreshMacsFanControl()
        guard canProbe else { return nil }
        probeStep = "Bắt đầu"
        defer { probeStep = nil }
        return await FanControlProbe(client: client, pause: pause).run { probeStep = $0 }
    }

    /// "Gỡ helper".
    func uninstall() async {
        guard !isBusy else { return }
        comparison = nil
        // The fans go back to Apple before the helper is taken away.
        await giveFansBack()
        // Nothing registered, nothing to remove: asking macOS to would only make it say so as an error.
        guard registration.status != .notRegistered, registration.status != .notFound else {
            set(.notInstalled)
            return
        }
        set(.busy(.removing))
        do {
            try await registration.unregister()
        } catch where Self.isJobNotFound(error) {
            // Already gone.
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
        if registration.status == .notRegistered || registration.status == .notFound { await install() } else { await settleAfterChange() }
    }

    // MARK: What the app does by itself

    /// Looks at the registration and, when the helper is enabled and not known to be running, asks it who it is. Never registers.
    /// Called when the tab or Settings appears; it does nothing while an install or removal is under way.
    func refresh() async {
        refreshMacsFanControl()
        guard !isBusy else { return }
        let status = registration.status
        // The error a register attempt gave stays on screen: macOS still says "not found" after it, which would wipe it.
        if case .failed = phase, status == .notRegistered || status == .notFound { return }
        if case .running = phase, status == .enabled { return }
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

    /// Looks at the status until it says approval is wanted (or the helper is enabled), for at most `approvalLooks` looks.
    private func waitForApprovalToShow() async {
        for _ in 0..<Self.approvalLooks {
            let status = registration.status
            if status == .requiresApproval || status == .enabled { return }
            await pause(Self.approvalLookInterval)
        }
    }

    private func settleAfterChange() async {
        await readState()
    }

    /// The phase that the registration status says, and for an enabled helper what a ping says.
    private func readState() async {
        switch registration.status {
        case .notRegistered, .notFound: set(.notInstalled)
        case .requiresApproval: set(.needsApproval)
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

    static let notAccepted = "macOS không nhận helper sau khi đăng ký"

    /// What a throwing `register()` means for the next step.
    enum RegisterOutcome: Equatable {
        case denied
        case alreadyRegistered
        /// "Operation not permitted" (code 1): what macOS 26.5 throws for a daemon that waits for the user's approval, while it
        /// posts the approval request and, a moment later, moves the status to `requiresApproval`.
        case notPermitted
        case other
    }

    /// How long `install()` waits for the status to catch up with a "not permitted": 10 looks, 200 ms apart.
    static let approvalLooks = 10
    static let approvalLookInterval = Duration.milliseconds(200)

    static let serviceManagementDomain = "SMAppServiceErrorDomain"
    /// EPERM, which is not in `SMErrors.h`.
    static let notPermittedCode = 1

    static func outcome(of error: any Error) -> RegisterOutcome {
        let nsError = error as NSError
        guard nsError.domain == serviceManagementDomain else { return .other }
        if nsError.code == notPermittedCode { return .notPermitted }
        switch nsError.code {
        case kSMErrorLaunchDeniedByUser: return .denied
        case kSMErrorAlreadyRegistered: return .alreadyRegistered
        default: return .other
        }
    }

    static func isJobNotFound(_ error: any Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == serviceManagementDomain && nsError.code == kSMErrorJobNotFound
    }

    /// A short Vietnamese reason for an error with its code, and never a path; the details are in the log.
    static func describe(_ error: any Error) -> String {
        switch error as? FanHelperError {
        case .timeout: return "helper không trả lời"
        case .noProxy: return "không mở được kết nối"
        case let .helperFailed(reason): return "helper báo: \(reason)"
        case nil:
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && (nsError.code == 4097 || nsError.code == 4099) {
                return "không có helper nào trả lời"
            }
            if nsError.domain == serviceManagementDomain, let reason = serviceManagementReasons[nsError.code] {
                return "\(reason) (SMAppService \(nsError.code))"
            }
            return "\(withoutPaths(nsError.localizedDescription)) (\(nsError.domain) \(nsError.code))"
        }
    }

    /// The codes of `SMErrors.h`, in words.
    private static let serviceManagementReasons: [Int: String] = [
        kSMErrorInternalFailure: "lỗi nội bộ của macOS",
        kSMErrorInvalidSignature: "chữ ký của ứng dụng không hợp lệ",
        kSMErrorAuthorizationFailure: "không đủ quyền",
        kSMErrorToolNotValid: "helper không hợp lệ",
        kSMErrorJobNotFound: "macOS không có job của helper",
        kSMErrorServiceUnavailable: "dịch vụ nền của macOS chưa sẵn sàng",
        kSMErrorJobPlistNotFound: "không tìm thấy file plist của helper trong ứng dụng",
        kSMErrorJobMustBeEnabled: "job của helper chưa được bật",
        kSMErrorInvalidPlist: "file plist của helper không hợp lệ",
        kSMErrorLaunchDeniedByUser: "chưa được cho phép trong Cài đặt hệ thống",
        kSMErrorAlreadyRegistered: "đã đăng ký rồi",
    ]

    /// Any word that starts with a slash is a path, and a path does not belong in a line on the screen.
    static func withoutPaths(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: false)
            .map { $0.contains("/") ? "…" : String($0) }
            .joined(separator: " ")
    }
}
