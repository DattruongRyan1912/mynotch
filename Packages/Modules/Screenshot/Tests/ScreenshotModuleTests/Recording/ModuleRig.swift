import CoreGraphics
import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import ScreenshotModule

/// The module wired to fakes inside a registry harness, with a 100×80 pt display at scale 2. Nothing in it captures a screen,
/// records, opens a microphone, a window or the pasteboard.
final class ModuleRig {
    static let display = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 80), scale: 2)
    /// What the overlay answers to a recording: 40×50 pixels of the display, which the recording gets as they are.
    static let selected = CaptureResult.region(displayID: 1, pixelRect: CGRect(x: 20, y: 30, width: 40, height: 50))

    let service = FakeCaptureService()
    let overlay = FakeOverlay()
    let pasteboard = FakePasteboard()
    let system = FakeSystem()
    /// Where the clean-up rules come from for a module that was never started: the user's own settings are never read.
    let fallbackSettings = SettingsStore(defaults: makeIsolatedDefaults())
    let module: ScreenshotModule
    let harness: RegistryHarness
    /// The harness's temporary storage root, removed with the rig.
    let temporaryRoot: URL
    private let dragsDirectory: URL

    init(recording: RecordingDependencies) throws {
        let system = system
        dragsDirectory = FileManager.default.temporaryDirectory.appending(path: "MyNotchTests-drags-\(UUID().uuidString)", directoryHint: .isDirectory)
        module = ScreenshotModule(
            service: service, overlay: overlay, recognizer: FakeRecognizer(), pasteboard: pasteboard,
            chip: FakeCaptureChip(), makeEditors: { _ in FakeEditors() },
            hasScreenAccess: { system.hasScreenAccess }, onScreenWindows: { system.windows },
            saveDirectory: { _ in system.saveDirectory }, dragCopiesDirectory: dragsDirectory, recording: recording,
            storageFallbackSettings: fallbackSettings
        )
        harness = RegistryHarness([module])
        harness.permissions.statuses = [.screenRecording: .granted, .microphone: .granted, .accessibility: .granted]
        temporaryRoot = harness.storageRoot.applicationSupport.deletingLastPathComponent()
        service.frozen = [FrozenDisplay(info: Self.display, image: try Self.picture())]
        overlay.result = Self.selected
    }

    deinit {
        try? FileManager.default.removeItem(at: temporaryRoot)
        try? FileManager.default.removeItem(at: dragsDirectory)
    }

    private static func picture() throws -> CGImage {
        try Bitmap(width: 200, height: 160) { x, y in Bitmap.Pixel(r: UInt8(x), g: UInt8(y), b: 0, a: 255) }.image()
    }

    var storage: ModuleStorage { harness.storageRoot.storage(for: "screenshot") }
    var recordingsRoot: URL { storage.directory.appending(path: "Recordings", directoryHint: .isDirectory) }
    var recordingStore: RecordingStore { RecordingStore(root: recordingsRoot) }
    var phase: RecordingPhase { module.state.recordingPhase }
    var activity: LiveActivity? { harness.activities.current?.activity }

    func start() async {
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "screenshot") == .running)
    }

    func settings() throws -> (ModuleSettings, ScreenshotSettingKeys) {
        let settings = try #require(harness.settingsEnvironment(for: "screenshot")).settings
        return (settings, ScreenshotSettingKeys(settings))
    }

    func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(2)) }
    }

    /// A recording on disk, as a session leaves one: a project, and a segment file of `bytes` bytes.
    @discardableResult
    func makeRecording(
        status: RecordingProject.Status = .finished, createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000), bytes: Int = 1_000,
        exportedAt: Date? = nil
    ) throws -> RecordingProject {
        let made = try recordingStore.create()
        var project = FakeRecorder.project(id: made.id, region: nil, status: status, seconds: 5)
        project.createdAt = createdAt
        project.exportedAt = exportedAt
        try project.write(to: made.folder)
        try Data(count: bytes).write(to: made.folder.appending(path: "segment-001.mov"))
        return project
    }
}
