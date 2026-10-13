import CoreGraphics
import Foundation
import ImageIO
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import ScreenshotModule

@Suite final class ScreenshotModuleTests {
    /// One 100×80 pt display at scale 2 whose pixel (x, y) has red x and green y, so a crop's origin can be read back.
    static let displayInfo = DisplayInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 80), scale: 2)
    static let region = CaptureResult.region(displayID: 1, pixelRect: CGRect(x: 20, y: 30, width: 40, height: 50))

    let service = FakeCaptureService()
    let overlay = FakeOverlay()
    let recognizer = FakeRecognizer()
    let pasteboard = FakePasteboard()
    let system = FakeSystem()
    let module: ScreenshotModule
    let harness: RegistryHarness
    /// The harness's temporary storage root, removed when the test ends.
    let temporaryRoot: URL
    /// Where the module puts the copies it offers for dragging, so tests never share the real folder.
    let dragsDirectory: URL

    init() throws {
        let system = system
        let dragsDirectory = FileManager.default.temporaryDirectory.appending(path: "MyNotchTests-drags-\(UUID().uuidString)", directoryHint: .isDirectory)
        self.dragsDirectory = dragsDirectory
        module = ScreenshotModule(
            service: service, overlay: overlay, recognizer: recognizer, pasteboard: pasteboard,
            hasScreenAccess: { system.hasScreenAccess }, onScreenWindows: { system.windows },
            saveDirectory: { _ in system.saveDirectory },
            dragCopiesDirectory: dragsDirectory
        )
        harness = RegistryHarness([module])
        harness.permissions.statuses[.screenRecording] = .granted
        temporaryRoot = harness.storageRoot.applicationSupport.deletingLastPathComponent()
        service.frozen = [FrozenDisplay(info: Self.displayInfo, image: try Self.gradient(width: 200, height: 160))]
        overlay.result = Self.region
    }

    deinit {
        try? FileManager.default.removeItem(at: temporaryRoot)
        try? FileManager.default.removeItem(at: dragsDirectory)
    }

    static func gradient(width: Int, height: Int) throws -> CGImage {
        try Bitmap(width: width, height: height) { x, y in Bitmap.Pixel(r: UInt8(x), g: UInt8(y), b: 0, a: 255) }.image()
    }

    func start() async {
        await harness.registry.bootstrap()
        #expect(harness.registry.state(of: "screenshot") == .running)
    }

    func settings() throws -> (ModuleSettings, ScreenshotSettingKeys) {
        let settings = try #require(harness.settingsEnvironment(for: "screenshot")).settings
        return (settings, ScreenshotSettingKeys(settings))
    }

    func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { try? await Task.sleep(for: .milliseconds(2)) }
    }

    func dpi(of url: URL) throws -> Double? {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (properties[kCGImagePropertyDPIWidth] as? Double)?.rounded()
    }

    var activity: LiveActivity? { harness.activities.current?.activity }

    // MARK: Lifecycle

    @Test func descriptorAndTabMatchTheSpec() throws {
        #expect(module.descriptor.id == "screenshot")
        #expect(module.descriptor.displayName == "Ảnh chụp")
        #expect(module.descriptor.systemImage == "camera.viewfinder")
        #expect(module.descriptor.order == 300)
        #expect(module.descriptor.permissions == [.screenRecording])
        let tab = try #require(module.makeTab())
        #expect(tab.id == "screenshot")
        #expect(tab.title == "Ảnh chụp")
        #expect(tab.preferredHeight == 200)
    }

    @Test func settingsRowsExistWhetherOrNotTheModuleRuns() throws {
        let environment = try #require(harness.settingsEnvironment(for: "screenshot"))
        #expect(module.makeSettingsView(environment) != nil)
    }

    @Test func startRegistersTheCaptureAndOCRHotkeys() async throws {
        await start()

        #expect(harness.hotkeys.registrations.map(\.id) == ["screenshot_capture", "screenshot_ocr"])
        #expect(harness.hotkeys.registrations.map(\.title) == ["Chụp màn hình", "OCR vùng chọn"])
        let capture = try #require(harness.hotkeys.registrations.first)
        let ocr = try #require(harness.hotkeys.registrations.last)
        #expect(harness.hotkeyBackend.getShortcut(for: capture.name) == KeyboardShortcuts.Shortcut(.s, modifiers: [.control, .option]))
        #expect(harness.hotkeyBackend.getShortcut(for: ocr.name) == KeyboardShortcuts.Shortcut(.o, modifiers: [.control, .option]))

        await harness.registry.setEnabled(false, for: "screenshot")
        #expect(harness.hotkeys.registrations.isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func theHotkeysStartTheirModes() async {
        await start()
        overlay.result = nil

        #expect(harness.hotkeyBackend.trigger("screenshot_capture"))
        await waitUntil { overlay.runs.count == 1 }
        #expect(harness.hotkeyBackend.trigger("screenshot_ocr"))
        await waitUntil { overlay.runs.count == 2 }

        #expect(overlay.runs.map(\.mode) == [.regionOrWindow, .ocrRegion])
    }

    @Test func startLoadsTheCapturesOnDisk() async throws {
        let storage = harness.storageRoot.storage(for: "screenshot")
        try storage.ensureDirectories()
        let earlier = CaptureStore(directory: storage.directory, cachesDirectory: storage.cachesDirectory, logger: Log.logger(category: "ScreenshotModuleTests"))
        let record = try await earlier.add(Self.gradient(width: 10, height: 10), keepCount: 30)

        await start()

        #expect(module.state.records.map(\.id) == [record.id])
    }

    @Test func stopCancelsTheOverlayAndClearsTheTray() async throws {
        await start()
        await module.capture(mode: .regionOrWindow)
        #expect(module.state.records.count == 1)

        await harness.registry.setEnabled(false, for: "screenshot")

        #expect(overlay.cancelCount == 1)
        #expect(module.state.records.isEmpty)
        #expect(module.ocrTask == nil)
    }

    // MARK: Capture

    @Test func missingPermissionShowsAToastInsteadOfTheOverlay() async {
        await start()
        system.hasScreenAccess = false

        await module.capture(mode: .regionOrWindow)

        #expect(harness.presenter.toastCount == 1)
        #expect(service.freezeCount == 0)
        #expect(overlay.runs.isEmpty)
        #expect(module.state.records.isEmpty)
    }

    @Test(arguments: [CaptureError.permissionDenied, .noDisplays, .failed("boom")])
    func freezeFailuresShowAToastAndNoOverlay(error: CaptureError) async {
        await start()
        service.freezeError = error

        await module.capture(mode: .regionOrWindow)

        #expect(harness.presenter.toastCount == 1)
        #expect(overlay.runs.isEmpty)
        #expect(pasteboard.images.isEmpty)
    }

    @Test func noDisplaysIsAFailureEvenWithoutAnError() async {
        await start()
        service.frozen = []

        await module.capture(mode: .regionOrWindow)

        #expect(harness.presenter.toastCount == 1)
        #expect(overlay.runs.isEmpty)
    }

    @Test func theOverlayIsShownOnEveryFrozenDisplayWithTheCurrentWindows() async {
        await start()
        let window = CapturableWindow(id: 12, ownerPID: 7, layer: 0, bounds: CGRect(x: 10, y: 10, width: 60, height: 40))
        system.windows = [window]

        await module.capture(mode: .regionOrWindow)

        #expect(overlay.runs.count == 1)
        #expect(overlay.runs[0].mode == .regionOrWindow)
        #expect(overlay.runs[0].frozen.map(\.info) == [Self.displayInfo])
        #expect(overlay.runs[0].windows == [window])
    }

    @Test func cancellingTheOverlayCapturesNothing() async {
        await start()
        overlay.result = nil

        await module.capture(mode: .regionOrWindow)

        #expect(module.state.records.isEmpty)
        #expect(pasteboard.images.isEmpty)
        #expect(activity == nil)
        #expect(harness.presenter.toastCount == 0)
    }

    @Test func regionStoresTheCroppedImageCopiesItAndAnnouncesIt() async throws {
        await start()

        await module.capture(mode: .regionOrWindow)

        let record = try #require(module.state.records.first)
        #expect((record.pixelWidth, record.pixelHeight) == (40, 50))
        let store = try #require(module.store)
        let url = try #require(store.url(for: record.id))
        #expect(try dpi(of: url) == 144)

        let copied = try #require(pasteboard.images.first)
        #expect(pasteboard.images.count == 1)
        #expect((copied.image.width, copied.image.height, copied.scale) == (40, 50, 2))
        let bitmap = try Bitmap(copied.image)
        #expect(bitmap.pixel(0, 0) == Bitmap.Pixel(r: 20, g: 30, b: 0, a: 255))
        #expect(bitmap.pixel(39, 49) == Bitmap.Pixel(r: 59, g: 79, b: 0, a: 255))

        #expect(activity?.id == "captured")
        #expect(activity?.expiresAfter == .seconds(3))
        harness.scheduler.advance(by: .seconds(3))
        #expect(activity == nil)
        #expect(harness.presenter.toastCount == 0)
    }

    @Test func fullScreenStoresTheWholeDisplay() async throws {
        await start()
        overlay.result = .fullScreen(displayID: 1)

        await module.capture(mode: .regionOrWindow)

        let record = try #require(module.state.records.first)
        #expect((record.pixelWidth, record.pixelHeight) == (200, 160))
        #expect(pasteboard.images.first?.image.width == 200)
    }

    @Test func aResultForAnUnknownDisplayStoresNothing() async {
        await start()
        overlay.result = .fullScreen(displayID: 99)

        await module.capture(mode: .regionOrWindow)

        #expect(module.state.records.isEmpty)
        #expect(pasteboard.images.isEmpty)
    }

    @Test func aRegionOutsideTheImageStoresNothing() async {
        await start()
        overlay.result = .region(displayID: 1, pixelRect: CGRect(x: 500, y: 500, width: 10, height: 10))

        await module.capture(mode: .regionOrWindow)

        #expect(module.state.records.isEmpty)
        #expect(pasteboard.images.isEmpty)
    }

    @Test func windowIsCapturedAgainAtTheScaleOfItsDisplay() async throws {
        await start()
        // Its centre, (40, 30) in CG points, is (40, 50) in AppKit points: on the scale 2 display.
        system.windows = [CapturableWindow(id: 12, ownerPID: 7, layer: 0, bounds: CGRect(x: 10, y: 10, width: 60, height: 40))]
        service.windowImage = try Self.gradient(width: 120, height: 80)
        overlay.result = .window(12)

        await module.capture(mode: .regionOrWindow)

        #expect(service.windowCaptures.count == 1)
        #expect(service.windowCaptures.first?.id == 12)
        #expect(service.windowCaptures.first?.includeShadow == true)
        let record = try #require(module.state.records.first)
        #expect((record.pixelWidth, record.pixelHeight) == (120, 80))
        #expect(try dpi(of: #require(module.store?.url(for: record.id))) == 144)
        #expect(pasteboard.images.first?.image.width == 120)
        #expect(activity?.id == "captured")
    }

    @Test func windowShadowFollowsTheSetting() async throws {
        await start()
        let (settings, keys) = try settings()
        settings.set(false, for: keys.windowShadow)
        service.windowImage = try Self.gradient(width: 120, height: 80)
        overlay.result = .window(12)

        await module.capture(mode: .regionOrWindow)

        #expect(service.windowCaptures.first?.includeShadow == false)
    }

    @Test func aFailedWindowCaptureShowsAToastAndStoresNothing() async {
        await start()
        service.windowError = .failed("gone")
        overlay.result = .window(12)

        await module.capture(mode: .regionOrWindow)

        #expect(harness.presenter.toastCount == 1)
        #expect(module.state.records.isEmpty)
        #expect(pasteboard.images.isEmpty)
    }

    @Test func copyToClipboardCanBeTurnedOff() async throws {
        await start()
        let (settings, keys) = try settings()
        settings.set(false, for: keys.copyToClipboard)

        await module.capture(mode: .regionOrWindow)

        #expect(module.state.records.count == 1)
        #expect(pasteboard.images.isEmpty)
        #expect(activity?.id == "captured")
    }

    @Test func theCapturedActivityCanBeTurnedOff() async throws {
        await start()
        let (settings, keys) = try settings()
        settings.set(false, for: keys.showCapturedActivity)

        await module.capture(mode: .regionOrWindow)

        #expect(module.state.records.count == 1)
        #expect(activity == nil)
    }

    @Test func keepCountIsRespected() async throws {
        await start()
        let (settings, keys) = try settings()
        settings.set(5, for: keys.keepCount)

        for _ in 0..<7 { await module.capture(mode: .regionOrWindow) }

        #expect(module.state.records.count == 5)
        #expect(module.store?.records.count == 5)
    }

    @Test func aFailedStoreStillCopiesTheImageAndSaysSo() async throws {
        await start()
        // A file where the captures folder should be makes every write fail.
        let storage = harness.storageRoot.storage(for: "screenshot")
        try FileManager.default.createDirectory(at: storage.directory, withIntermediateDirectories: true)
        try Data().write(to: storage.directory.appending(path: "captures"))

        await module.capture(mode: .regionOrWindow)

        #expect(module.state.records.isEmpty)
        #expect(harness.presenter.toastCount == 1)
        #expect(pasteboard.images.count == 1)
        #expect(activity == nil)
    }

    @Test(.timeLimit(.minutes(1))) func aSecondHotkeyWhileTheOverlayIsUpIsIgnored() async {
        await start()
        overlay.isGated = true
        let first = Task { await module.capture(mode: .regionOrWindow) }
        await waitUntil { overlay.runs.count == 1 }

        await module.capture(mode: .regionOrWindow)
        #expect(service.freezeCount == 1)

        overlay.release(Self.region)
        await first.value
        #expect(module.state.records.count == 1)
        // Once the overlay is gone the hotkey works again.
        overlay.isGated = false
        await module.capture(mode: .regionOrWindow)
        #expect(service.freezeCount == 2)
        #expect(module.state.records.count == 2)
    }

    @Test(.timeLimit(.minutes(1))) func aCaptureStillWaitingOnTheOverlayWhenTheModuleStopsStoresNothing() async {
        await start()
        overlay.isGated = true
        let capture = Task { await module.capture(mode: .regionOrWindow) }
        await waitUntil { overlay.runs.count == 1 }

        await harness.registry.setEnabled(false, for: "screenshot")
        await capture.value

        #expect(overlay.cancelCount == 1)
        #expect(pasteboard.images.isEmpty)
        #expect(module.state.records.isEmpty)
    }

    // MARK: OCR

    @Test func ocrRecognisesTheRegionCopiesTheTextAndStoresNothing() async throws {
        await start()
        recognizer.text = "Xin chào thế giới"

        await module.capture(mode: .ocrRegion)
        await module.ocrTask?.value

        #expect(overlay.runs.first?.mode == .ocrRegion)
        #expect(recognizer.calls.count == 1)
        #expect(recognizer.calls.first?.size == CGSize(width: 40, height: 50))
        #expect(recognizer.calls.first?.languages == OCRService.defaultLanguages)
        #expect(pasteboard.texts == ["Xin chào thế giới"])
        #expect(pasteboard.images.isEmpty)
        #expect(module.state.records.isEmpty)
        #expect(activity?.id == "ocr")
        #expect(activity?.expiresAfter == .seconds(3))
        #expect(OCRMessage.copied(characters: 17).text == "Đã chép 17 ký tự")
    }

    @Test func ocrUsesTheConfiguredLanguages() async throws {
        await start()
        let (settings, keys) = try settings()
        settings.set(["fr-FR"], for: keys.ocrLanguages)

        await module.capture(mode: .ocrRegion)
        await module.ocrTask?.value

        #expect(recognizer.calls.first?.languages == ["fr-FR"])
    }

    @Test func ocrOfAFullScreenSelectionReadsTheWholeDisplay() async {
        await start()
        overlay.result = .fullScreen(displayID: 1)

        await module.capture(mode: .ocrRegion)
        await module.ocrTask?.value

        #expect(recognizer.calls.first?.size == CGSize(width: 200, height: 160))
    }

    @Test func ocrIgnoresAWindowResultSinceItOffersNone() async {
        await start()
        overlay.result = .window(12)

        await module.capture(mode: .ocrRegion)

        #expect(service.windowCaptures.isEmpty)
        #expect(recognizer.calls.isEmpty)
    }

    @Test(arguments: ["", "  \n\t "])
    func ocrWithoutTextSaysSoAndKeepsTheClipboard(text: String) async {
        await start()
        recognizer.text = text

        await module.capture(mode: .ocrRegion)
        await module.ocrTask?.value

        #expect(pasteboard.texts.isEmpty)
        #expect(activity?.id == "ocr")
        #expect(activity?.expiresAfter == .seconds(3))
        #expect(OCRMessage.noText.text == "Không thấy chữ")
    }

    @Test(.timeLimit(.minutes(1))) func ocrShowsProgressUntilItIsDone() async throws {
        await start()
        recognizer.isGated = true

        await module.capture(mode: .ocrRegion)
        await waitUntil { recognizer.calls.count == 1 }
        #expect(activity?.id == "ocr")
        #expect(activity?.expiresAfter == nil)
        #expect(OCRMessage.recognizing.text == "Đang nhận chữ…")
        #expect(pasteboard.texts.isEmpty)

        recognizer.release()
        await module.ocrTask?.value
        #expect(pasteboard.texts == ["Xin chào"])
        #expect(activity?.expiresAfter == .seconds(3))
    }

    @Test(.timeLimit(.minutes(1))) func aNewCaptureCancelsTheRunningOCR() async throws {
        await start()
        recognizer.isGated = true
        await module.capture(mode: .ocrRegion)
        await waitUntil { recognizer.calls.count == 1 }
        let running = try #require(module.ocrTask)

        // The new capture is cancelled from its overlay, as with Esc.
        overlay.result = nil
        await module.capture(mode: .regionOrWindow)
        #expect(activity == nil)

        recognizer.release()
        await running.value
        #expect(pasteboard.texts.isEmpty)
        #expect(activity == nil)
    }

    @Test func aFailedOCRClearsTheProgressAndShowsAToast() async {
        await start()
        recognizer.error = CaptureError.failed("vision")

        await module.capture(mode: .ocrRegion)
        await module.ocrTask?.value

        #expect(activity == nil)
        #expect(harness.presenter.toastCount == 1)
        #expect(pasteboard.texts.isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func stoppingTheModuleCancelsTheOCR() async throws {
        await start()
        recognizer.isGated = true
        await module.capture(mode: .ocrRegion)
        await waitUntil { recognizer.calls.count == 1 }
        let running = try #require(module.ocrTask)

        await harness.registry.setEnabled(false, for: "screenshot")
        recognizer.release()
        await running.value

        #expect(pasteboard.texts.isEmpty)
        #expect(module.ocrTask == nil)
    }

    @Test func aFailedTextCopyShowsAToast() async {
        await start()
        pasteboard.succeeds = false

        await module.capture(mode: .ocrRegion)
        await module.ocrTask?.value

        #expect(harness.presenter.toastCount == 1)
    }

    @Test(.timeLimit(.minutes(1))) func aHotkeyWithoutPermissionLeavesARunningOCRAlone() async throws {
        await start()
        recognizer.isGated = true
        await module.capture(mode: .ocrRegion)
        await waitUntil { recognizer.calls.count == 1 }
        let running = try #require(module.ocrTask)
        system.hasScreenAccess = false

        await module.capture(mode: .regionOrWindow)
        #expect(!running.isCancelled)
        #expect(activity?.id == "ocr")

        recognizer.release()
        await running.value
        #expect(pasteboard.texts == ["Xin chào"])
    }

    // MARK: Tray

    func capturedRecord() async throws -> CaptureRecord {
        await start()
        await module.capture(mode: .regionOrWindow)
        return try #require(module.state.records.first)
    }

    @Test func copyPutsTheStoredImageOnThePasteboard() async throws {
        let record = try await capturedRecord()
        let before = pasteboard.images.count

        await module.copy(record)

        #expect(pasteboard.images.count == before + 1)
        #expect(pasteboard.images.last?.image.width == 40)
        #expect(pasteboard.images.last?.scale == 2)
        #expect(harness.presenter.toastCount == 1)
    }

    @Test func saveCopiesTheImageToTheChosenFolder() async throws {
        let record = try await capturedRecord()
        let folder = temporaryRoot.appending(path: "Desktop", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        system.saveDirectory = folder

        await module.save(record)

        let saved = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(saved.count == 1)
        #expect(saved.first?.hasPrefix("Ảnh chụp ") == true)
        #expect(saved.first?.hasSuffix(".png") == true)
        #expect(harness.presenter.toastCount == 1)
    }

    @Test func saveWithoutAFolderShowsAToast() async throws {
        let record = try await capturedRecord()
        system.saveDirectory = nil

        await module.save(record)

        #expect(harness.presenter.toastCount == 1)
    }

    @Test func saveAsOverwritesWhatThePanelConfirmed() async throws {
        let record = try await capturedRecord()
        let destination = temporaryRoot.appending(path: "chosen.png")
        try Data("old".utf8).write(to: destination)

        await module.export(record, to: destination)

        let source = try #require(CGImageSourceCreateWithURL(destination as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 1)
        #expect(try Data(contentsOf: destination) == pngData(of: record))
        #expect(harness.presenter.toastCount == 1)
    }

    @Test func aFailedSaveAsKeepsTheFileItWasToReplace() async throws {
        let record = try await capturedRecord()
        let destination = temporaryRoot.appending(path: "chosen.png")
        try Data("old".utf8).write(to: destination)
        // With the stored PNG gone the copy fails, as a full disk would make it.
        try FileManager.default.removeItem(at: #require(module.store?.url(for: record.id)))
        let toasts = harness.presenter.toastCount

        await module.export(record, to: destination)

        #expect(try Data(contentsOf: destination) == Data("old".utf8))
        #expect(harness.presenter.toastCount == toasts + 1)
    }

    @Test func deleteRemovesTheCaptureAndItsFile() async throws {
        let record = try await capturedRecord()
        let url = try #require(module.store?.url(for: record.id))

        module.delete(record)

        #expect(module.state.records.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func ocrFromTheTrayReportsWithToastsNotActivities() async throws {
        let record = try await capturedRecord()
        harness.scheduler.advance(by: .seconds(3))
        let toasts = harness.presenter.toastCount

        await module.recognizeText(in: record)
        await module.ocrTask?.value

        #expect(recognizer.calls.last?.size == CGSize(width: 40, height: 50))
        #expect(pasteboard.texts == ["Xin chào"])
        #expect(activity == nil)
        #expect(harness.presenter.toastCount > toasts)
    }

    @Test func thumbnailsComeFromTheStore() async throws {
        let record = try await capturedRecord()

        let thumbnail = await module.thumbnail(for: record, maxPixel: 20)

        #expect(max(thumbnail?.width ?? 0, thumbnail?.height ?? 0) == 20)
    }

    @Test func draggingOffersAReadablyNamedLinkOrCopy() async throws {
        let record = try await capturedRecord()
        let stored = try #require(module.store?.url(for: record.id))

        let url = try #require(module.dragFileURL(for: record))

        #expect(url.lastPathComponent.hasPrefix("Ảnh chụp "))
        #expect(url.pathExtension == "png")
        #expect(url != stored)
        #expect(url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == dragsDirectory.standardizedFileURL)
        #expect(FileManager.default.contentsEqual(atPath: url.path(percentEncoded: false), andPath: stored.path(percentEncoded: false)))
        // Same volume, so no second copy of the pixels is written on the main actor.
        let inodes = try [url, stored].map { try #require(FileManager.default.attributesOfItem(atPath: $0.path(percentEncoded: false))[.systemFileNumber] as? Int) }
        #expect(inodes[0] == inodes[1])
    }

    @Test func startRemovesDragCopiesOfEarlierRuns() async throws {
        let leftover = dragsDirectory.appending(path: "earlier", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: leftover.appending(path: "old.png"))

        await start()

        #expect(!FileManager.default.fileExists(atPath: leftover.path(percentEncoded: false)))
    }
}
