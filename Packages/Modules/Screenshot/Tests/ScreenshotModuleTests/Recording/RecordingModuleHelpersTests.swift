import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import ScreenshotModule

/// The small pure parts the module's recording is made of.
@Suite struct RecordingModuleHelpersTests {
    // MARK: Microphone

    let usb = MicrophoneDevice(id: "USB-1", name: "USB")

    @Test func theMicrophoneSettingIsTheDefaultNoneOrADevice() {
        #expect(MicrophoneChoice.selection(for: MicrophoneChoice.systemDefault, available: [usb]) == .systemDefault)
        #expect(MicrophoneChoice.selection(for: MicrophoneChoice.off, available: [usb]) == nil)
        #expect(MicrophoneChoice.selection(for: "USB-1", available: [usb]) == .device("USB-1"))
    }

    @Test func aDeviceThatIsNotConnectedAnyMoreIsTheSystemsDefault() {
        #expect(MicrophoneChoice.selection(for: "USB-1", available: []) == .systemDefault)
        #expect(MicrophoneChoice.selection(for: "garbage", available: [usb]) == .systemDefault)
    }

    // MARK: Defaults

    @Test func theDefaultsAreWrittenOverTheFourThingsTheyAreAndNothingElse() throws {
        let folder = try TestFolder("defaults")
        var project = FakeRecorder.project(id: UUID(), region: nil, status: .finished, seconds: 5)
        project.cuts = [CutRange(start: 1, end: 2)]
        project.zoomRules.zoomInDuration = 0.9
        project.zoomSegments = []
        try project.write(to: folder.url)

        try RecordingDefaults(exportLevel: .high, zoomScale: 2.5, zoomHoldSeconds: 3, clickEffect: false).write(to: folder.url)

        var expected = project
        expected.exportLevel = .high
        expected.zoomRules.scale = 2.5
        expected.zoomRules.idleTimeout = 3
        expected.clickEffect = false
        #expect(try RecordingProject.load(from: folder.url) == expected)
    }

    @Test func defaultsForAFolderWithoutAProjectThrowAndCreateNothing() throws {
        let folder = try TestFolder("defaults-missing")
        #expect(throws: (any Error).self) {
            try RecordingDefaults(exportLevel: .chat, zoomScale: 2, zoomHoldSeconds: 1.5, clickEffect: true).write(to: folder.url)
        }
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: folder.url.path)) ?? []).isEmpty)
    }

    // MARK: Settings

    @Test func theRecordingSettingsStartAtTheStandardRulesAndStayInTheEditorsLimits() throws {
        let (settings, keys) = try ModuleRig(recording: FakeRecordingSystem().dependencies).settings()

        #expect(settings.value(keys.recordMicrophone) == MicrophoneChoice.systemDefault)
        #expect(!settings.value(keys.recordSystemAudio))
        #expect(settings.value(keys.recordCountdown))
        #expect(settings.value(keys.zoomScale) == ZoomRules.standard.scale)
        #expect(settings.value(keys.zoomHoldSeconds) == ZoomRules.standard.idleTimeout)
        #expect(settings.value(keys.clickEffect))
        #expect(settings.value(keys.exportLevel) == .chat)

        settings.set(9.0, for: keys.zoomScale)
        settings.set(0.0, for: keys.zoomHoldSeconds)
        #expect(settings.value(keys.zoomScale) == 3 && settings.value(keys.zoomHoldSeconds) == 0.5)
        settings.set(0.1, for: keys.zoomScale)
        settings.set(60.0, for: keys.zoomHoldSeconds)
        #expect(settings.value(keys.zoomScale) == 1.25 && settings.value(keys.zoomHoldSeconds) == 5)
    }

    // MARK: Text

    @Test func theClockReadsMinutesAndSecondsThenHours() {
        #expect(RecordingElapsed.text(0) == "00:00")
        #expect(RecordingElapsed.text(83.9) == "01:23")
        #expect(RecordingElapsed.text(3599) == "59:59")
        #expect(RecordingElapsed.text(3723) == "1:02:03")
        #expect(RecordingElapsed.text(-4) == "00:00")
    }

    @Test func aRowSaysHowLongHowBigAndWhetherItWasCutShort() {
        let folder = URL(filePath: "/tmp/x")
        let whole = RecordingSummary(id: UUID(), folder: folder, createdAt: .now, duration: 83, bytes: 1_500_000, isIncomplete: false)
        let cut = RecordingSummary(id: UUID(), folder: folder, createdAt: .now, duration: 5, bytes: 2_000_000, isIncomplete: true)

        #expect(RecordingRowView.detail(of: whole) == "01:23 · \(ByteCountFormatter.string(fromByteCount: 1_500_000, countStyle: .file))")
        #expect(RecordingRowView.detail(of: cut).hasSuffix("quay dở") && !RecordingRowView.detail(of: whole).contains("quay dở"))
        #expect(RecordingListView.total(of: [whole, cut]) == "2 bản quay, \(ByteCountFormatter.string(fromByteCount: 3_500_000, countStyle: .file))")
    }

    @Test func theWholeScreenAloneNeedsNoOverlayMode() {
        #expect(RecordingTarget.screen.selectionMode == nil)
        #expect(RecordingTarget.window.selectionMode == .recordWindow)
        #expect(RecordingTarget.region.selectionMode == .recordRegion)
        #expect(RecordingTarget.any.selectionMode == .recordRegionOrWindow)
    }

    @Test func onlyAnIdlePhaseIsFreeAndOnlyRecordingOrPausedHasARecording() {
        let phases: [RecordingPhase] = [.idle, .selecting, .countdown(2), .starting, .recording, .paused, .stopping]
        #expect(phases.filter { !$0.isBusy } == [.idle])
        #expect(phases.filter(\.hasRecording) == [.recording, .paused])
    }
}
