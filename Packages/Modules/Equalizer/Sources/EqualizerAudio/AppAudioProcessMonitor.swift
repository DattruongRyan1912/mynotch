import AppKit
import Darwin
import Foundation
import MyNotchCore

/// Resolved information about a process playing audio.
public struct ResolvedProcessInfo: Sendable, Equatable {
    public var pid: pid_t
    public var name: String
    public var bundleID: String?
    public var isControllable: Bool
    public var defaultNotice: String?

    public init(
        pid: pid_t,
        name: String,
        bundleID: String? = nil,
        isControllable: Bool = true,
        defaultNotice: String? = nil
    ) {
        self.pid = pid
        self.name = name
        self.bundleID = bundleID
        self.isControllable = isControllable
        self.defaultNotice = defaultNotice
    }
}

/// Abstraction for resolving process hierarchy and application identities.
public protocol ProcessMetadataProviding: Sendable {
    func resolve(pid: pid_t) -> ResolvedProcessInfo?
}

/// Production metadata provider inspecting macOS process trees and application bundles.
public struct SystemProcessMetadataProvider: ProcessMetadataProviding {
    public init() {}

    public func resolve(pid: pid_t) -> ResolvedProcessInfo? {
        let runningApp = NSRunningApplication(processIdentifier: pid)
        let initialBundleID = runningApp?.bundleIdentifier
        let initialName = runningApp?.localizedName ?? Self.processName(for: pid) ?? "App (\(pid))"
        let initialPath = Self.processPath(for: pid)

        let helper = Self.isHelperProcess(name: initialName, bundleID: initialBundleID, path: initialPath)

        if helper {
            // 1. Traverse parent process tree
            var currentPID = pid
            var visited: Set<pid_t> = [pid]
            var resolvedParent: NSRunningApplication?

            for _ in 0..<8 {
                guard let ppid = Self.parentPID(for: currentPID), ppid > 1, !visited.contains(ppid) else {
                    break
                }
                visited.insert(ppid)
                if let parent = NSRunningApplication(processIdentifier: ppid),
                   let pBundleID = parent.bundleIdentifier,
                   !Self.isHelperProcess(name: parent.localizedName ?? "", bundleID: pBundleID, path: nil) {
                    resolvedParent = parent
                    break
                }
                currentPID = ppid
            }

            if let parent = resolvedParent, let pBundleID = parent.bundleIdentifier {
                let (controllable, notice) = Self.checkControllability(bundleID: pBundleID)
                return ResolvedProcessInfo(
                    pid: parent.processIdentifier,
                    name: parent.localizedName ?? Self.processName(for: parent.processIdentifier) ?? "App",
                    bundleID: pBundleID,
                    isControllable: controllable,
                    defaultNotice: notice
                )
            }

            // 2. Fallback: Parse path to locate outermost .app bundle
            if let path = initialPath, let appRange = path.range(of: ".app", options: .backwards) {
                let outerAppPath = String(path[..<appRange.upperBound])
                if let bundle = Bundle(path: outerAppPath),
                   let outerBundleID = bundle.bundleIdentifier {
                    let cfBundleName = bundle.infoDictionary?["CFBundleName"] as? String
                    let cfDisplayName = bundle.infoDictionary?["CFBundleDisplayName"] as? String
                    let fallbackName = (outerAppPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
                    let outerName = cfBundleName ?? cfDisplayName ?? fallbackName
                    let running = NSRunningApplication.runningApplications(withBundleIdentifier: outerBundleID).first
                    let primaryPID = running?.processIdentifier ?? pid
                    let (controllable, notice) = Self.checkControllability(bundleID: outerBundleID)
                    return ResolvedProcessInfo(
                        pid: primaryPID,
                        name: running?.localizedName ?? outerName,
                        bundleID: outerBundleID,
                        isControllable: controllable,
                        defaultNotice: notice
                    )
                }
            }
        }

        let (controllable, notice) = Self.checkControllability(bundleID: initialBundleID)
        return ResolvedProcessInfo(
            pid: pid,
            name: initialName,
            bundleID: initialBundleID,
            isControllable: controllable,
            defaultNotice: notice
        )
    }

    public static func isHelperProcess(name: String, bundleID: String?, path: String?) -> Bool {
        if let bID = bundleID?.lowercased(), bID.contains(".helper") || bID.contains(".xpc") {
            return true
        }
        let lowerName = name.lowercased()
        if lowerName.contains("helper") || lowerName.contains("renderer") || lowerName.contains("gpu") ||
            lowerName.contains("web content") || lowerName.contains("webkit") || lowerName.contains("plugin") {
            return true
        }
        if bundleID == nil {
            return true
        }
        return false
    }

    public static func parentPID(for pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.stride
        let result = proc_pidinfo(pid, 3, 0, &info, Int32(size)) // 3 == PROC_PIDTBSDINFO
        guard result == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    public static func processPath(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return buffer.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return nil }
            return String(validatingCString: base)
        }
    }

    public static func processName(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return buffer.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return nil }
            return String(validatingCString: base)
        }
    }

    public static func checkControllability(bundleID: String?) -> (Bool, String?) {
        guard let bundleID = bundleID else {
            return (false, "Chỉ đọc / Không hỗ trợ điều khiển")
        }
        let id = bundleID.lowercased()

        // Scriptable Players
        if id == "com.spotify.client" ||
           id == "com.apple.music" ||
           id == "com.apple.quicktimeplayerx" ||
           id == "org.videolan.vlc" ||
           id == "com.colliderli.iina" ||
           id == "com.apple.tv" ||
           id == "com.apple.podcasts" {
            return (true, nil)
        }

        // Scriptable Chromium Browsers
        if id == "com.google.chrome" ||
           id == "com.google.chrome.canary" ||
           id == "com.brave.browser" ||
           id == "company.thebrowser.browser" ||
           id == "com.microsoft.edgemac" ||
           id == "com.vivaldi.vivaldi" ||
           id == "com.operasoftware.opera" {
            return (true, nil)
        }

        // Scriptable WebKit Browsers
        if id == "com.apple.safari" ||
           id == "com.apple.safaritechnologypreview" {
            return (true, nil)
        }

        return (false, "Chỉ đọc / Không hỗ trợ điều khiển")
    }
}

/// Monitors running audio applications on the Mac, resolves application identities,
/// and synchronizes active playback processes with `AppVolumeState`.
@MainActor
public final class AppAudioProcessMonitor: Sendable {
    private let audioSystem: any AudioSystem
    public let appVolumeState: AppVolumeState
    private let metadataProvider: any ProcessMetadataProviding
    private var observationToken: AnyObject?
    private var isStarted = false

    /// Optional custom volume dispatcher (used for testing or overriding default AppleScript dispatching).
    public var customVolumeDispatcher: (@Sendable (String, Double) -> Void)?

    /// Optional Chrome/Chromium native extension volume dispatcher. Returns true if handled natively.
    public var chromeVolumeDispatcher: (@MainActor @Sendable (Double, Bool) -> Bool)?

    /// Optional script execution hook (for unit tests to simulate errors without running real AppleScript).
    public typealias ScriptExecutionResult = (success: Bool, errorNumber: Int?, errorMessage: String?)
    public var scriptExecutor: (@Sendable (String) -> ScriptExecutionResult)?

    public init(
        audioSystem: any AudioSystem,
        appVolumeState: AppVolumeState,
        metadataProvider: (any ProcessMetadataProviding)? = nil
    ) {
        self.audioSystem = audioSystem
        self.appVolumeState = appVolumeState
        self.metadataProvider = metadataProvider ?? SystemProcessMetadataProvider()
    }

    /// Starts observing CoreAudio process events and performs an initial refresh.
    public func start() {
        guard !isStarted else { return }
        isStarted = true
        refresh()
        observationToken = audioSystem.observeChanges(
            { [weak self] in
                Task { @MainActor [weak self] in
                    self?.refresh()
                }
            },
            volumeChanged: {}
        )
    }

    /// Stops observation and detaches listener tokens.
    public func stop() {
        isStarted = false
        observationToken = nil
    }

    /// Inspects active CoreAudio output processes, resolves application metadata,
    /// and updates `AppVolumeState.runningApps`.
    public func refresh() {
        let ownPID = getpid()
        let processes = audioSystem.activeProcesses()

        var discovered: [RunningAudioApp] = []
        var seenAppIDs = Set<String>()
        let ignoredDaemons: Set<String> = [
            "coreaudiod",
            "launchd",
            "screencapture",
            "systemsoundserverd",
            "rapportd",
            "distnoted"
        ]

        for process in processes where process.isRunningOutput && process.pid != ownPID {
            guard let resolved = metadataProvider.resolve(pid: process.pid) else {
                continue
            }

            if ignoredDaemons.contains(resolved.name.lowercased()) {
                continue
            }

            let appID = resolved.bundleID ?? "pid.\(resolved.pid)"
            if seenAppIDs.insert(appID).inserted {
                let notice = appVolumeState.controlNotice(for: appID) ?? resolved.defaultNotice
                discovered.append(RunningAudioApp(
                    id: appID,
                    pid: resolved.pid,
                    name: resolved.name,
                    bundleID: resolved.bundleID,
                    isPlaying: true,
                    isControllable: resolved.isControllable,
                    controlNotice: notice
                ))
            }
        }

        appVolumeState.updateRunningApps(discovered)

        // Apply saved rules to discovered apps
        for app in discovered where app.isControllable {
            let effVol = appVolumeState.volume(for: app.id)
            dispatchVolume(effVol, to: app)
        }
    }

    /// Updates volume in `AppVolumeState` and dispatches to the application.
    public func setVolume(_ volume: Double, for app: RunningAudioApp) {
        appVolumeState.setVolume(volume, for: app.id)
        let effective = appVolumeState.volume(for: app.id)
        dispatchVolume(effective, to: app)
    }

    /// Toggles mute in `AppVolumeState` and dispatches effective volume.
    public func toggleMute(for app: RunningAudioApp) {
        appVolumeState.toggleMute(for: app.id)
        let effective = appVolumeState.volume(for: app.id)
        dispatchVolume(effective, to: app)
    }

    /// Resets volume to 100% (unmuted).
    public func resetVolume(for app: RunningAudioApp) {
        appVolumeState.reset(for: app.id)
        let effective = appVolumeState.volume(for: app.id)
        dispatchVolume(effective, to: app)
    }

    // MARK: - Volume Dispatching

    public static func isChromiumBrowser(bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        return id == "com.google.chrome" ||
               id == "com.google.chrome.canary" ||
               id == "com.brave.browser" ||
               id == "company.thebrowser.browser" ||
               id == "com.microsoft.edgemac" ||
               id == "com.vivaldi.vivaldi" ||
               id == "com.operasoftware.opera"
    }

    private func dispatchVolume(_ volume: Double, to app: RunningAudioApp) {
        if let customDispatcher = customVolumeDispatcher {
            customDispatcher(app.id, volume)
            return
        }

        guard app.isControllable, let bundleID = app.bundleID else { return }

        let isMuted = appVolumeState.isMuted(for: app.id)

        // Native extension bridge fast-path for Chrome & Chromium browsers
        if Self.isChromiumBrowser(bundleID: bundleID), let chromeDispatcher = chromeVolumeDispatcher {
            if chromeDispatcher(volume, isMuted) {
                if self.appVolumeState.controlNotice(for: app.id) != nil {
                    self.appVolumeState.setControlNotice(nil, for: app.id)
                }
                return
            }
        }

        // Negative constraint 5: Never send AppleScript commands to non-running apps in production
        if scriptExecutor == nil {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
                return
            }
        }

        // Avoid firing real AppleScript in automated tests unless a custom scriptExecutor is provided
        if Self.isRunningTests && scriptExecutor == nil {
            return
        }

        guard let scriptSource = Self.appleScriptCommand(for: bundleID, volume: volume, isMuted: isMuted) else {
            return
        }

        let executor = self.scriptExecutor ?? Self.defaultExecuteAppleScript
        Task.detached(priority: .utility) { [weak self, appID = app.id] in
            let result = executor(scriptSource)
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if !result.success {
                    if result.errorNumber == 12 || (result.errorMessage?.contains("JavaScript through AppleScript is turned off") == true) {
                        self.appVolumeState.setControlNotice(
                            "Cần bật: View > Developer > Allow JavaScript from Apple Events",
                            for: appID
                        )
                    } else if result.errorNumber == -1743 {
                        self.appVolumeState.setControlNotice(
                            "Cần cấp quyền Tự động hoá (Automation) trong Cài đặt Hệ thống",
                            for: appID
                        )
                    }
                } else {
                    // Success, clear any transient notice
                    if self.appVolumeState.controlNotice(for: appID) != nil {
                        self.appVolumeState.setControlNotice(nil, for: appID)
                    }
                }
            }
        }
    }

    /// Generates AppleScript to control volume for supported players and browsers.
    public static func appleScriptCommand(for bundleID: String, volume: Double, isMuted: Bool) -> String? {
        let safeVolume = min(max(volume, 0.0), 1.5)
        let effectiveVol = isMuted ? 0.0 : safeVolume
        let normVol = min(max(effectiveVol, 0.0), 1.0)
        let intVol = Int((normVol * 100.0).rounded())
        let id = bundleID.lowercased()

        if id == "com.spotify.client" {
            return "tell application id \"com.spotify.client\" to set sound volume to \(intVol)"
        }
        if id == "com.apple.music" {
            return "tell application id \"com.apple.Music\" to set sound volume to \(intVol)"
        }
        if id == "org.videolan.vlc" {
            let vlcVol = Int((normVol * 256.0).rounded())
            return "tell application id \"org.videolan.vlc\" to set audio volume to \(vlcVol)"
        }
        if id == "com.apple.quicktimeplayerx" {
            let qtVol = String(format: "%.2f", normVol)
            return "tell application id \"com.apple.QuickTimePlayerX\" to set audio volume of documents to \(qtVol)"
        }
        if id == "com.colliderli.iina" {
            return "tell application id \"com.colliderli.iina\" to set volume to \(intVol)"
        }
        if id == "com.apple.tv" {
            return "tell application id \"com.apple.TV\" to set sound volume to \(intVol)"
        }
        if id == "com.apple.podcasts" {
            return "tell application id \"com.apple.podcasts\" to set sound volume to \(intVol)"
        }

        // Chromium Browsers
        if id == "com.google.chrome" ||
           id == "com.google.chrome.canary" ||
           id == "com.brave.browser" ||
           id == "company.thebrowser.browser" ||
           id == "com.microsoft.edgemac" ||
           id == "com.vivaldi.vivaldi" ||
           id == "com.operasoftware.opera" {
            let jsVol = String(format: "%.3f", normVol)
            let jsMuted = isMuted ? "true" : "false"
            return """
            tell application id "\(bundleID)"
                if (count of windows) > 0 then
                    repeat with w in windows
                        repeat with t in tabs of w
                            execute t javascript "document.querySelectorAll('video, audio').forEach(function(el) { el.volume = \(jsVol); el.muted = \(jsMuted); });"
                        end repeat
                    end repeat
                end if
            end tell
            """
        }

        // Safari
        if id == "com.apple.safari" ||
           id == "com.apple.safaritechnologypreview" {
            let jsVol = String(format: "%.3f", normVol)
            let jsMuted = isMuted ? "true" : "false"
            return """
            tell application id "\(bundleID)"
                if (count of windows) > 0 then
                    repeat with w in windows
                        repeat with t in tabs of w
                            do JavaScript "document.querySelectorAll('video, audio').forEach(function(el) { el.volume = \(jsVol); el.muted = \(jsMuted); });" in t
                        end repeat
                    end repeat
                end if
            end tell
            """
        }

        return nil
    }

    private static let defaultExecuteAppleScript: @Sendable (String) -> ScriptExecutionResult = { source in
        guard let script = NSAppleScript(source: source) else {
            return (false, nil, "Failed to compile AppleScript")
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        if let err = error {
            let errorNumber = err[NSAppleScript.errorNumber] as? Int
            let message = err[NSAppleScript.errorMessage] as? String
            return (false, errorNumber, message)
        }
        return (true, nil, nil)
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.arguments.contains(where: { $0.contains("xctest") || $0.contains("testing-library") })
    }
}
