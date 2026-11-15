import Foundation
import Observation
import Testing
@testable import MyNotchCore
import MyNotchTestSupport

@MainActor
@Suite struct AppVolumeStateTests {
    final class Launches {
        let defaults = makeIsolatedDefaults()
        func launch() -> AppVolumeState { AppVolumeState(settings: SettingsStore(defaults: defaults)) }
    }

    @Test func seedsDefaultVolumeOfOneHundredPercentForNewApp() {
        let state = Launches().launch()
        let app = RunningAudioApp(id: "com.spotify.client", pid: 1234, name: "Spotify", bundleID: "com.spotify.client")
        state.updateRunningApps([app])

        #expect(state.rawVolume(for: app.id) == 1.0)
        #expect(state.isMuted(for: app.id) == false)
        #expect(state.volume(for: app.id) == 1.0)
    }

    @Test func volumeClampingAndNaNProtection() {
        let state = Launches().launch()
        let appID = "com.google.Chrome"

        // Clamps below 0
        state.setVolume(-0.5, for: appID)
        #expect(state.rawVolume(for: appID) == 0.0)

        // Clamps above 1.5 (or max boost)
        state.setVolume(2.5, for: appID)
        #expect(state.rawVolume(for: appID) == 1.5)

        // Normal range
        state.setVolume(0.65, for: appID)
        #expect(abs(state.rawVolume(for: appID) - 0.65) < 0.001)

        // NaN and Infinity safety
        state.setVolume(.nan, for: appID)
        #expect(abs(state.rawVolume(for: appID) - 0.65) < 0.001) // preserves previous value or defaults

        state.setVolume(.infinity, for: appID)
        #expect(abs(state.rawVolume(for: appID) - 0.65) < 0.001)
    }

    @Test func muteTogglePreservesSavedVolume() {
        let state = Launches().launch()
        let appID = "com.apple.Music"

        state.setVolume(0.72, for: appID)
        #expect(state.volume(for: appID) == 0.72)
        #expect(state.isMuted(for: appID) == false)

        // Mute
        state.toggleMute(for: appID)
        #expect(state.isMuted(for: appID) == true)
        #expect(state.volume(for: appID) == 0.0) // effective volume is 0
        #expect(state.rawVolume(for: appID) == 0.72) // raw saved volume preserved!

        // Unmute
        state.toggleMute(for: appID)
        #expect(state.isMuted(for: appID) == false)
        #expect(state.volume(for: appID) == 0.72)
    }

    @Test func persistsRuleAcrossLaunches() {
        let launches = Launches()
        let first = launches.launch()
        let appID = "tv.plex.desktop"

        first.setVolume(0.35, for: appID)
        first.setMuted(true, for: appID)

        let second = launches.launch()
        #expect(second.rawVolume(for: appID) == 0.35)
        #expect(second.isMuted(for: appID) == true)
        #expect(second.volume(for: appID) == 0.0)

        // Reset to 100%
        second.reset(for: appID)
        #expect(second.rawVolume(for: appID) == 1.0)
        #expect(second.isMuted(for: appID) == false)
        #expect(second.volume(for: appID) == 1.0)
    }

    @Test func updateRunningAppsFiltersDuplicatesAndPreservesOrder() {
        let state = Launches().launch()
        let app1 = RunningAudioApp(id: "com.spotify.client", pid: 101, name: "Spotify")
        let app2 = RunningAudioApp(id: "com.apple.Music", pid: 102, name: "Music")
        let app1Dup = RunningAudioApp(id: "com.spotify.client", pid: 101, name: "Spotify Duplicate")

        state.updateRunningApps([app1, app2, app1Dup])
        #expect(state.runningApps.count == 2)
        #expect(state.runningApps.map(\.id) == ["com.spotify.client", "com.apple.Music"])
    }

    @Test func controlNoticeAndControllabilityState() {
        let state = Launches().launch()
        let app = RunningAudioApp(
            id: "com.google.Chrome",
            pid: 4154,
            name: "Google Chrome",
            bundleID: "com.google.Chrome",
            isPlaying: true,
            isControllable: true,
            controlNotice: nil
        )
        state.updateRunningApps([app])
        #expect(state.runningApps.first?.isControllable == true)
        #expect(state.runningApps.first?.controlNotice == nil)

        // Set notice (e.g. Chrome JS events disabled)
        state.setControlNotice("Cần bật: View > Developer > Allow JavaScript from Apple Events", for: "com.google.Chrome")
        #expect(state.runningApps.first?.controlNotice == "Cần bật: View > Developer > Allow JavaScript from Apple Events")
        #expect(state.controlNotice(for: "com.google.Chrome") == "Cần bật: View > Developer > Allow JavaScript from Apple Events")

        // Subsequent updateRunningApps preserves notice
        let refreshedApp = RunningAudioApp(
            id: "com.google.Chrome",
            pid: 4154,
            name: "Google Chrome",
            bundleID: "com.google.Chrome",
            isPlaying: true,
            isControllable: true
        )
        state.updateRunningApps([refreshedApp])
        #expect(state.runningApps.first?.controlNotice == "Cần bật: View > Developer > Allow JavaScript from Apple Events")

        // Clearing notice
        state.setControlNotice(nil, for: "com.google.Chrome")
        #expect(state.runningApps.first?.controlNotice == nil)
        #expect(state.controlNotice(for: "com.google.Chrome") == nil)
    }

    @Test func nonControllableAppAttributes() {
        let state = Launches().launch()
        let discord = RunningAudioApp(
            id: "com.hnc.Discord",
            pid: 9999,
            name: "Discord",
            bundleID: "com.hnc.Discord",
            isPlaying: true,
            isControllable: false,
            controlNotice: "Chỉ đọc / Không hỗ trợ điều khiển"
        )
        state.updateRunningApps([discord])
        #expect(state.runningApps.first?.isControllable == false)
        #expect(state.runningApps.first?.controlNotice == "Chỉ đọc / Không hỗ trợ điều khiển")
    }
}
