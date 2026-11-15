import EqualizerAudio
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing

@MainActor
@Suite("AppAudioProcessMonitor Tests")
struct AppAudioProcessMonitorTests {
    final class MockProcessMetadataProvider: ProcessMetadataProviding, @unchecked Sendable {
        private var table: [pid_t: ResolvedProcessInfo] = [:]

        func register(_ pid: pid_t, resolved: ResolvedProcessInfo) {
            table[pid] = resolved
        }

        func resolve(pid: pid_t) -> ResolvedProcessInfo? {
            table[pid]
        }
    }

    @Test func discoversRunningAudioProcessesAndExcludesSelf() async throws {
        let fakeAudio = FakeAudioSystem()
        let defaults = makeIsolatedDefaults()
        let settings = SettingsStore(defaults: defaults)
        let state = AppVolumeState(settings: settings)
        let monitor = AppAudioProcessMonitor(audioSystem: fakeAudio, appVolumeState: state)

        let ownPID = getpid()
        let mockProcesses = [
            ProcessOutput(pid: ownPID, isRunningOutput: true, deviceUIDs: ["speakers"]),
            ProcessOutput(pid: 9991, isRunningOutput: true, deviceUIDs: ["speakers"]),
            ProcessOutput(pid: 9992, isRunningOutput: false, deviceUIDs: []),
        ]
        fakeAudio.setProcesses(mockProcesses)

        monitor.refresh()

        #expect(!state.runningApps.contains { $0.pid == ownPID })
        #expect(state.runningApps.contains { $0.pid == 9991 })
        #expect(!state.runningApps.contains { $0.pid == 9992 })
    }

    @Test func volumeAdjustmentsTriggerVolumeDispatcher() async throws {
        let fakeAudio = FakeAudioSystem()
        let defaults = makeIsolatedDefaults()
        let settings = SettingsStore(defaults: defaults)
        let state = AppVolumeState(settings: settings)
        let monitor = AppAudioProcessMonitor(audioSystem: fakeAudio, appVolumeState: state)

        let mockProcesses = [
            ProcessOutput(pid: 8881, isRunningOutput: true, deviceUIDs: ["speakers"])
        ]
        fakeAudio.setProcesses(mockProcesses)

        nonisolated final class DispatchRecorder: @unchecked Sendable {
            private let lock = NSLock()
            private var items: [(String, Double)] = []
            func record(_ appID: String, _ vol: Double) {
                lock.lock()
                defer { lock.unlock() }
                items.append((appID, vol))
            }
            var last: (String, Double)? {
                lock.lock()
                defer { lock.unlock() }
                return items.last
            }
        }
        let recorder = DispatchRecorder()

        monitor.customVolumeDispatcher = { appID, vol in
            recorder.record(appID, vol)
        }

        monitor.refresh()
        guard let app = state.runningApps.first(where: { $0.pid == 8881 }) else {
            Issue.record("Expected app with PID 8881 to be discovered")
            return
        }

        // Adjust volume to 75%
        monitor.setVolume(0.75, for: app)
        #expect(state.rawVolume(for: app.id) == 0.75)
        #expect(state.volume(for: app.id) == 0.75)
        #expect(recorder.last?.1 == 0.75)

        // Toggle mute
        monitor.toggleMute(for: app)
        #expect(state.isMuted(for: app.id) == true)
        #expect(state.volume(for: app.id) == 0.0)
        #expect(recorder.last?.1 == 0.0)

        // Reset volume
        monitor.resetVolume(for: app)
        #expect(state.isMuted(for: app.id) == false)
        #expect(state.volume(for: app.id) == 1.0)
        #expect(recorder.last?.1 == 1.0)
    }

    @Test func audioObservationTriggersRefresh() async throws {
        let fakeAudio = FakeAudioSystem()
        let defaults = makeIsolatedDefaults()
        let settings = SettingsStore(defaults: defaults)
        let state = AppVolumeState(settings: settings)
        let monitor = AppAudioProcessMonitor(audioSystem: fakeAudio, appVolumeState: state)

        monitor.start()
        #expect(fakeAudio.isObserved)

        // Update processes and fire change
        fakeAudio.setProcesses([
            ProcessOutput(pid: 7771, isRunningOutput: true, deviceUIDs: ["speakers"])
        ])
        fakeAudio.fireChange()

        // Wait a tiny bit for the Task on MainActor
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(state.runningApps.contains { $0.pid == 7771 })

        monitor.stop()
    }

    // MARK: - Test Case 1: Parent Process Resolution & Helper Deduplication

    @Test func resolvesHelperProcessesToParentAppAndDeduplicatesStreams() async throws {
        let fakeAudio = FakeAudioSystem()
        let defaults = makeIsolatedDefaults()
        let settings = SettingsStore(defaults: defaults)
        let state = AppVolumeState(settings: settings)
        let mockMeta = MockProcessMetadataProvider()

        // Two Chrome helper processes (Renderer and GPU) both mapping to parent Google Chrome
        let chromeParent = ResolvedProcessInfo(
            pid: 19000,
            name: "Google Chrome",
            bundleID: "com.google.Chrome",
            isControllable: true,
            defaultNotice: nil
        )
        mockMeta.register(19123, resolved: chromeParent)
        mockMeta.register(19124, resolved: chromeParent)

        let monitor = AppAudioProcessMonitor(audioSystem: fakeAudio, appVolumeState: state, metadataProvider: mockMeta)

        fakeAudio.setProcesses([
            ProcessOutput(pid: 19123, isRunningOutput: true, deviceUIDs: ["speakers"]),
            ProcessOutput(pid: 19124, isRunningOutput: true, deviceUIDs: ["speakers"])
        ])

        monitor.refresh()

        // Deduplication invariant: 2 helpers from same parent app collapse into 1 entry
        #expect(state.runningApps.count == 1)
        guard let chromeApp = state.runningApps.first else {
            Issue.record("Expected 1 running app")
            return
        }
        #expect(chromeApp.id == "com.google.Chrome")
        #expect(chromeApp.name == "Google Chrome")
        #expect(chromeApp.bundleID == "com.google.Chrome")
        #expect(chromeApp.pid == 19000)
        #expect(chromeApp.isControllable == true)
        #expect(chromeApp.controlNotice == nil)
    }

    // MARK: - Test Case 2: Multi-Player & Browser AppleScript Command Generation

    @Test func generatesAccurateAppleScriptForSupportedApps() throws {
        // Spotify: 60%
        let spotifyCmd = AppAudioProcessMonitor.appleScriptCommand(for: "com.spotify.client", volume: 0.6, isMuted: false)
        #expect(spotifyCmd == "tell application id \"com.spotify.client\" to set sound volume to 60")

        // Apple Music: 45%
        let musicCmd = AppAudioProcessMonitor.appleScriptCommand(for: "com.apple.Music", volume: 0.45, isMuted: false)
        #expect(musicCmd == "tell application id \"com.apple.Music\" to set sound volume to 45")

        // VLC: 50% (50% of 256 is 128)
        let vlcCmd = AppAudioProcessMonitor.appleScriptCommand(for: "org.videolan.vlc", volume: 0.5, isMuted: false)
        #expect(vlcCmd == "tell application id \"org.videolan.vlc\" to set audio volume to 128")

        // QuickTime: 80%
        let qtCmd = AppAudioProcessMonitor.appleScriptCommand(for: "com.apple.QuickTimePlayerX", volume: 0.8, isMuted: false)
        #expect(qtCmd == "tell application id \"com.apple.QuickTimePlayerX\" to set audio volume of documents to 0.80")

        // Chrome: 60% unmuted
        let chromeCmd = AppAudioProcessMonitor.appleScriptCommand(for: "com.google.Chrome", volume: 0.6, isMuted: false)
        #expect(chromeCmd != nil)
        #expect(chromeCmd?.contains("tell application id \"com.google.Chrome\"") == true)
        #expect(chromeCmd?.contains("document.querySelectorAll('video, audio').forEach") == true)
        #expect(chromeCmd?.contains("el.volume = 0.600") == true)
        #expect(chromeCmd?.contains("el.muted = false") == true)

        // Chrome: muted
        let chromeMutedCmd = AppAudioProcessMonitor.appleScriptCommand(for: "com.google.Chrome", volume: 0.6, isMuted: true)
        #expect(chromeMutedCmd?.contains("el.volume = 0.000") == true)
        #expect(chromeMutedCmd?.contains("el.muted = true") == true)

        // Safari: 30% unmuted
        let safariCmd = AppAudioProcessMonitor.appleScriptCommand(for: "com.apple.Safari", volume: 0.3, isMuted: false)
        #expect(safariCmd != nil)
        #expect(safariCmd?.contains("tell application id \"com.apple.Safari\"") == true)
        #expect(safariCmd?.contains("do JavaScript") == true)
        #expect(safariCmd?.contains("el.volume = 0.300") == true)

        // Unsupported app (e.g. Discord, Zoom) returns nil
        let discordCmd = AppAudioProcessMonitor.appleScriptCommand(for: "com.hnc.Discord", volume: 0.5, isMuted: false)
        #expect(discordCmd == nil)
    }

    // MARK: - Test Case 3: Process Tree & Helper Classification

    @Test func walksMultiLevelProcessTreeAndStopsAtCycleOrLaunchd() throws {
        // Test helper classification heuristics
        #expect(SystemProcessMetadataProvider.isHelperProcess(name: "Google Chrome Helper (GPU)", bundleID: "com.google.Chrome.helper", path: nil) == true)
        #expect(SystemProcessMetadataProvider.isHelperProcess(name: "Google Chrome Helper (Renderer)", bundleID: "com.google.Chrome.helper.renderer", path: nil) == true)
        #expect(SystemProcessMetadataProvider.isHelperProcess(name: "Safari Web Content", bundleID: "com.apple.WebKit.WebContent", path: nil) == true)
        #expect(SystemProcessMetadataProvider.isHelperProcess(name: "Google Chrome", bundleID: "com.google.Chrome", path: nil) == false)
        #expect(SystemProcessMetadataProvider.isHelperProcess(name: "Spotify", bundleID: "com.spotify.client", path: nil) == false)
        #expect(SystemProcessMetadataProvider.isHelperProcess(name: "Music", bundleID: "com.apple.Music", path: nil) == false)

        // Test Controllability checking
        let (chromeOk, chromeNotice) = SystemProcessMetadataProvider.checkControllability(bundleID: "com.google.Chrome")
        #expect(chromeOk == true)
        #expect(chromeNotice == nil)

        let (vlcOk, vlcNotice) = SystemProcessMetadataProvider.checkControllability(bundleID: "org.videolan.vlc")
        #expect(vlcOk == true)
        #expect(vlcNotice == nil)

        let (discordOk, discordNotice) = SystemProcessMetadataProvider.checkControllability(bundleID: "com.hnc.Discord")
        #expect(discordOk == false)
        #expect(discordNotice != nil)
    }

    // MARK: - Test Case 4: Non-Controllable Apps & Chrome JS AppleEvents Error Notice

    @Test func classifiesUnsupportedAppsAsReadOnlyAndCapturesChromeJSErrorNotice() async throws {
        let fakeAudio = FakeAudioSystem()
        let defaults = makeIsolatedDefaults()
        let settings = SettingsStore(defaults: defaults)
        let state = AppVolumeState(settings: settings)
        let mockMeta = MockProcessMetadataProvider()

        // 1. Unsupported app: Discord
        let discord = ResolvedProcessInfo(
            pid: 4001,
            name: "Discord",
            bundleID: "com.hnc.Discord",
            isControllable: false,
            defaultNotice: "Chỉ đọc / Không hỗ trợ điều khiển"
        )
        mockMeta.register(4001, resolved: discord)

        // 2. Controllable app: Google Chrome
        let chrome = ResolvedProcessInfo(
            pid: 4002,
            name: "Google Chrome",
            bundleID: "com.google.Chrome",
            isControllable: true,
            defaultNotice: nil
        )
        mockMeta.register(4002, resolved: chrome)

        let monitor = AppAudioProcessMonitor(audioSystem: fakeAudio, appVolumeState: state, metadataProvider: mockMeta)

        fakeAudio.setProcesses([
            ProcessOutput(pid: 4001, isRunningOutput: true, deviceUIDs: ["speakers"]),
            ProcessOutput(pid: 4002, isRunningOutput: true, deviceUIDs: ["speakers"])
        ])

        monitor.refresh()

        // Verify Discord is classified as non-controllable
        let discordApp = state.runningApps.first(where: { $0.id == "com.hnc.Discord" })
        #expect(discordApp?.isControllable == false)
        #expect(discordApp?.controlNotice == "Chỉ đọc / Không hỗ trợ điều khiển")

        // Verify Chrome initially has no notice
        let chromeApp = state.runningApps.first(where: { $0.id == "com.google.Chrome" })
        #expect(chromeApp?.isControllable == true)
        #expect(chromeApp?.controlNotice == nil)

        // Simulate Chrome throwing error 12 ("Executing JavaScript through AppleScript is turned off")
        monitor.scriptExecutor = { _ in
            (false, 12, "Google Chrome got an error: Executing JavaScript through AppleScript is turned off.")
        }

        if let app = chromeApp {
            monitor.setVolume(0.5, for: app)
        }

        // Wait for async task on MainActor
        try await Task.sleep(nanoseconds: 50_000_000)

        // Verify Chrome gets notice regarding "Allow JavaScript from Apple Events"
        let updatedChrome = state.runningApps.first(where: { $0.id == "com.google.Chrome" })
        #expect(updatedChrome?.controlNotice?.contains("Allow JavaScript from Apple Events") == true)

        // Simulate subsequent success
        monitor.scriptExecutor = { _ in
            (true, nil, nil)
        }

        if let app = updatedChrome {
            monitor.setVolume(0.7, for: app)
        }

        try await Task.sleep(nanoseconds: 50_000_000)

        // Notice is cleared on success
        let clearedChrome = state.runningApps.first(where: { $0.id == "com.google.Chrome" })
        #expect(clearedChrome?.controlNotice == nil)
    }

    // MARK: - Test Case 5: Native Extension Dispatcher Bypasses AppleScript

    @Test func chromeVolumeDispatcherBypassesAppleScriptWhenHandled() async throws {
        let fakeAudio = FakeAudioSystem()
        let defaults = makeIsolatedDefaults()
        let settings = SettingsStore(defaults: defaults)
        let state = AppVolumeState(settings: settings)
        let mockMeta = MockProcessMetadataProvider()

        let chromeAppInfo = ResolvedProcessInfo(
            pid: 20100,
            name: "Google Chrome",
            bundleID: "com.google.Chrome",
            isControllable: true,
            defaultNotice: nil
        )
        mockMeta.register(20100, resolved: chromeAppInfo)

        let monitor = AppAudioProcessMonitor(audioSystem: fakeAudio, appVolumeState: state, metadataProvider: mockMeta)

        fakeAudio.setProcesses([
            ProcessOutput(pid: 20100, isRunningOutput: true, deviceUIDs: ["speakers"])
        ])
        monitor.refresh()

        guard let chromeApp = state.runningApps.first(where: { $0.id == "com.google.Chrome" }) else {
            Issue.record("Expected Chrome app")
            return
        }

        nonisolated final class TestCallRecorder: @unchecked Sendable {
            private let lock = NSLock()
            private var _dispatcherCalls: [(Double, Bool)] = []
            private var _scriptCalls = 0

            func recordDispatcher(vol: Double, muted: Bool) {
                lock.lock()
                defer { lock.unlock() }
                _dispatcherCalls.append((vol, muted))
            }

            func recordScript() {
                lock.lock()
                defer { lock.unlock() }
                _scriptCalls += 1
            }

            var dispatcherCalls: [(Double, Bool)] {
                lock.lock()
                defer { lock.unlock() }
                return _dispatcherCalls
            }

            var scriptCalls: Int {
                lock.lock()
                defer { lock.unlock() }
                return _scriptCalls
            }
        }
        let box = TestCallRecorder()

        monitor.chromeVolumeDispatcher = { vol, muted in
            box.recordDispatcher(vol: vol, muted: muted)
            return true
        }

        monitor.scriptExecutor = { _ in
            box.recordScript()
            return (true, nil, nil)
        }

        monitor.setVolume(0.5, for: chromeApp)

        #expect(box.dispatcherCalls.count == 1)
        #expect(box.dispatcherCalls.first?.0 == 0.5)
        #expect(box.dispatcherCalls.first?.1 == false)
        #expect(box.scriptCalls == 0) // AppleScript completely bypassed!
        #expect(state.controlNotice(for: chromeApp.id) == nil)

        // Fallback case: if dispatcher returns false, fall through to scriptExecutor
        monitor.chromeVolumeDispatcher = { _, _ in false }
        monitor.setVolume(0.7, for: chromeApp)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(box.scriptCalls == 1) // Script executor was called as fallback
    }
}
