import Foundation
import MyNotchCore
import MyNotchTestSupport
import Observation
import Testing
@testable import MediaModule

@Suite struct MediaModuleTests {
    let source = FakeNowPlayingSource()
    let module: MediaModule
    let harness: RegistryHarness

    init() {
        module = MediaModule(source: source, lookUpApp: { _ in nil })
        harness = RegistryHarness([module])
    }

    var keys: MediaSettingsKeys { MediaSettingsKeys(harness.settingsEnvironment(for: "media")!.settings) }

    /// Lets the settings observation loop run after a settings write.
    func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() { await Task.yield() }
    }

    @Test func descriptor() {
        let descriptor = module.descriptor
        #expect(descriptor.id == "media")
        #expect(descriptor.displayName == "Media")
        #expect(descriptor.systemImage == "music.note")
        #expect(descriptor.defaultEnabled)
        #expect(descriptor.order == 200)
        #expect(descriptor.permissions.isEmpty)
        #expect(descriptor.optionalPermissions.isEmpty)
    }

    @Test func missingAdapterReportsUnavailable() async {
        for (script, framework) in [(nil, nil), (URL(filePath: "/tmp/a.pl"), nil), (nil, URL(filePath: "/tmp/A.framework"))] {
            let harness = RegistryHarness([MediaModule(adapterScript: script, adapterFramework: framework)])
            await harness.registry.bootstrap()
            #expect(harness.registry.state(of: "media") == .unavailable(reason: "Thiếu MediaRemoteAdapter trong app"))
        }
    }

    @Test func startsTheSourceAndShowsPlayback() async {
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "media") == .running)
        #expect(source.isStarted)
        #expect(harness.activities.current == nil)

        source.emit(AdapterLines.track())
        #expect(harness.activities.current?.id == "media/nowPlaying")
        #expect(harness.activities.current?.activity.priority == .normal)
        #expect(module.store.state.title == "Song")
        #expect(harness.registry.tabs.map(\.id) == ["media"])
    }

    @Test func tab() async throws {
        await harness.registry.bootstrap()
        let tab = try #require(harness.registry.tabs.first)
        #expect(tab.title == "Media")
        #expect(tab.systemImage == "music.note")
        #expect(tab.preferredHeight == 150)
        #expect(!tab.acceptsKeyboard)
    }

    @Test func pausedTrackHidesAfterTheGrace() async {
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        source.emit(AdapterLines.playing(false))
        #expect(harness.activities.current?.id == "media/nowPlaying")
        harness.scheduler.advance(by: .milliseconds(4900))
        #expect(harness.activities.current != nil)
        harness.scheduler.advance(by: .milliseconds(100))
        #expect(harness.activities.current == nil)
    }

    @Test func resumingWithinTheGraceKeepsTheActivity() async {
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        source.emit(AdapterLines.playing(false))
        harness.scheduler.advance(by: .seconds(3))
        source.emit(AdapterLines.playing(true))
        harness.scheduler.advance(by: .seconds(60))
        #expect(harness.activities.current?.id == "media/nowPlaying")
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func pauseGraceComesFromSettings() async {
        harness.settings.set(2, for: keys.pauseGraceSeconds)
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        source.emit(AdapterLines.playing(false))
        harness.scheduler.advance(by: .milliseconds(1900))
        #expect(harness.activities.current != nil)
        harness.scheduler.advance(by: .milliseconds(100))
        #expect(harness.activities.current == nil)
    }

    @Test func pauseGraceIsClamped() {
        let settings = harness.settingsEnvironment(for: "media")!.settings
        settings.set(500, for: keys.pauseGraceSeconds)
        #expect(settings.value(keys.pauseGraceSeconds) == 60)
        settings.set(-3, for: keys.pauseGraceSeconds)
        #expect(settings.value(keys.pauseGraceSeconds) == 0)
    }

    @Test func emptyPayloadHidesAfterTheTrackChangeDebounce() async {
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        source.emit(AdapterLines.empty)
        #expect(harness.activities.current != nil)
        harness.scheduler.advance(by: .milliseconds(300))
        #expect(harness.activities.current == nil)
    }

    @Test func turningShowActivityOnWhileATrackChangeIsPendingWaitsForTheTrack() async {
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        source.emit(AdapterLines.empty)
        harness.settings.set(false, for: keys.showActivity)
        await settle { harness.activities.current == nil }
        #expect(harness.activities.current == nil)

        // Still inside the 300 ms hiding window: nothing to show, so nothing is published.
        harness.settings.set(true, for: keys.showActivity)
        await settle { harness.activities.current != nil }
        #expect(harness.activities.current == nil)
        harness.scheduler.advance(by: .milliseconds(300))
        #expect(harness.activities.current == nil)

        source.emit(AdapterLines.track("Next"))
        #expect(harness.activities.current?.id == "media/nowPlaying")
    }

    @Test func showActivityOffNeverShows() async {
        harness.settings.set(false, for: keys.showActivity)
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        #expect(harness.activities.current == nil)
        #expect(module.store.state.isPlaying)
    }

    @Test func togglingShowActivityWhilePlaying() async {
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        harness.settings.set(false, for: keys.showActivity)
        await settle { harness.activities.current == nil }
        #expect(harness.activities.current == nil)
        harness.settings.set(true, for: keys.showActivity)
        await settle { harness.activities.current != nil }
        #expect(harness.activities.current?.id == "media/nowPlaying")
    }

    @Test func hiddenAppsNeverShow() async {
        harness.settings.set(["com.example.Player"], for: keys.hiddenApps)
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        #expect(harness.activities.current == nil)
        source.emit(AdapterLines.track(bundle: "com.example.Player.helper", parent: "com.example.Player"))
        #expect(harness.activities.current == nil)
        source.emit(AdapterLines.track(bundle: "com.other.Player"))
        #expect(harness.activities.current?.id == "media/nowPlaying")
    }

    @Test func hidingThePlayingAppInSettingsClearsTheActivity() async throws {
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        let environment = try #require(harness.settingsEnvironment(for: "media"))
        #expect(environment.isRunning)
        environment.settings.binding(keys.hiddenApps).wrappedValue = ["com.example.Player"]
        await settle { harness.activities.current == nil }
        #expect(harness.activities.current == nil)
    }

    @Test func onlyTrackChangesRepublish() async throws {
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track("First"))
        let first = try #require(harness.activities.current)

        source.emit(AdapterLines.position(31))
        source.emit(AdapterLines.position(45))
        source.emit(AdapterLines.playing(false))
        source.emit(AdapterLines.playing(true))
        #expect(harness.activities.current == first)

        // onChange is @Sendable but runs synchronously on the writing (main) thread in this test.
        nonisolated(unsafe) var changes = 0
        withObservationTracking { _ = harness.activities.current } onChange: { changes += 1 }
        source.emit(AdapterLines.track("Second"))
        #expect(changes == 1)
        let second = try #require(harness.activities.current)
        #expect(second != first)
        #expect(second.id == "media/nowPlaying")
        #expect(harness.activities.entries.count == 1)

        source.emit(AdapterLines.position(2))
        #expect(harness.activities.current == second)
    }

    @Test func playbackCommandsGoToTheSource() async {
        await harness.registry.bootstrap()
        module.send(.togglePlayPause)
        module.send(.nextTrack)
        module.seek(toSeconds: 42.5)
        #expect(source.sent == [.togglePlayPause, .nextTrack])
        #expect(source.seeks == [42.5])
    }

    @Test func tabButtonsSendTheirCommands() async {
        await harness.registry.bootstrap()
        let actions = module.actions
        for control in TransportControl.allCases { actions.send(control.command) }
        #expect(source.sent == [.previousTrack, .togglePlayPause, .nextTrack])

        let progress = PlaybackProgress(elapsed: 30, duration: 200)
        actions.seek(progress.seconds(atFraction: 0.25)!)
        #expect(source.seeks == [50])
    }

    @Test func commandsAreIgnoredWhileStopped() {
        module.send(.togglePlayPause)
        module.seek(toSeconds: 10)
        #expect(source.sent.isEmpty)
        #expect(source.seeks.isEmpty)
    }

    @Test func registersShortcutsWithoutDefaults() async {
        await harness.registry.bootstrap()
        let registrations = harness.hotkeys.registrations.filter { $0.owner == "media" }
        #expect(registrations.map(\.id) == ["media_mediaPlayPause", "media_mediaNext", "media_mediaPrevious"])
        #expect(registrations.map(\.title) == ["Phát/dừng nhạc", "Bài sau", "Bài trước"])
        #expect(registrations.allSatisfy { $0.name.initialShortcut == nil })
    }

    @Test func sourceFailureKeepsRunningAndExplains() async {
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        #expect(harness.activities.current != nil)

        source.fail("The media adapter failed to start 3 times in a row (status 1).")
        #expect(harness.registry.state(of: "media") == .running)
        #expect(module.store.failureMessage == "Không đọc được thông tin phát nhạc (macOS đã chặn adapter)")
        #expect(module.store.state == .empty)
        #expect(harness.activities.current == nil)
        #expect(harness.scheduler.pendingCount == 0)
    }

    @Test func commandsAfterAFailureDoNotReachTheDeadSource() async {
        await harness.registry.bootstrap()
        source.fail("gave up")
        // Each command would start a perl process that fails like the stream did.
        module.send(.togglePlayPause)
        module.seek(toSeconds: 10)
        #expect(source.sent.isEmpty)
        #expect(source.seeks.isEmpty)

        await harness.registry.retry("media")
        module.send(.nextTrack)
        #expect(source.sent == [.nextTrack])
    }

    @Test func stoppingStopsTheSourceAndForgetsPlayback() async {
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        source.emit(AdapterLines.playing(false))
        await harness.registry.setEnabled(false, for: "media")
        #expect(!source.isStarted)
        #expect(source.stopCount == 1)
        #expect(harness.activities.current == nil)
        #expect(module.store.state == .empty)
        #expect(harness.scheduler.pendingCount == 0)
        #expect(harness.hotkeys.registrations.isEmpty)

        await harness.registry.setEnabled(true, for: "media")
        #expect(source.startCount == 2)
        #expect(harness.activities.current == nil)
        source.emit(AdapterLines.track())
        #expect(harness.activities.current?.id == "media/nowPlaying")
    }

    @Test func restartClearsAnEarlierFailure() async {
        await harness.registry.bootstrap()
        source.fail("gave up")
        await harness.registry.retry("media")
        #expect(module.store.failureMessage == nil)
        #expect(source.isStarted)
    }

    @Test func settingsRowsExistWhileStopped() throws {
        #expect(harness.registry.state(of: "media") == .disabled)
        let environment = try #require(harness.settingsEnvironment(for: "media"))
        #expect(!environment.isRunning)
        let view = try #require(harness.registry.settingsView(for: "media"))
        #expect(String(describing: view).hasPrefix("AnyView(MediaSettingsView("))
    }

    @Test func settingsChangedWhileStoppedApplyOnStart() async throws {
        let environment = try #require(harness.settingsEnvironment(for: "media"))
        environment.settings.binding(keys.showActivity).wrappedValue = false
        await harness.registry.bootstrap()
        source.emit(AdapterLines.track())
        #expect(harness.activities.current == nil)
    }
}
