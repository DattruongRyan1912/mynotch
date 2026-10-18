import AppKit
import MyNotchCore
import SwiftUI

/// Screenshots in the notch: a hotkey freezes the screens, the overlay picks a region, window or display, and the
/// result goes to the tray, optionally the clipboard, and a chip with "Sửa" and "Chép" beside it. A second hotkey reads
/// the text of a region instead (OCR).
public final class ScreenshotModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "screenshot",
        displayName: "Ảnh chụp",
        systemImage: "camera.viewfinder",
        defaultEnabled: true,
        permissions: [.screenRecording],
        // Only the folder the "Lưu vào" setting points at is written; Pictures needs no permission.
        optionalPermissions: [.desktopFolder, .downloadsFolder],
        permissionReasons: [
            .screenRecording: "Chụp màn hình.",
            .desktopFolder: "Lưu ảnh vào Desktop (nơi lưu mặc định của “Lưu vào”).",
            .downloadsFolder: "Lưu ảnh vào Downloads khi chọn nơi lưu là Downloads.",
        ],
        order: 300
    )

    static let captureShortcut = KeyboardShortcuts.Shortcut(.s, modifiers: [.control, .option])
    static let ocrShortcut = KeyboardShortcuts.Shortcut(.o, modifiers: [.control, .option])

    let state = ScreenshotState()
    /// Set while running.
    private(set) var store: CaptureStore?
    /// The text recognition in progress or just finished; a new capture cancels it. Tests wait for it.
    private(set) var ocrTask: Task<Void, Never>?
    let pasteboard: any PasteboardWriting
    let recognizer: any TextRecognizing
    let saveDirectory: (SaveLocation) -> URL?
    /// Each drag of a capture gets its own folder here; `start` removes the folders of earlier runs.
    let dragCopiesDirectory: URL
    /// The markup editor's windows, made when the first one opens.
    var editors: (any MarkupEditorHosting)?
    /// The chip beside a new capture; set while running.
    private(set) var chip: CaptureChipController?
    private let chipPresenter: any CaptureChipPresenting
    let makeEditors: @MainActor (ScreenshotModule) -> any MarkupEditorHosting
    private(set) var context: ModuleContext?
    private(set) var keys: ScreenshotSettingKeys?
    private let service: any CaptureService
    private let overlay: any SelectionOverlay
    private let hasScreenAccess: () -> Bool
    private let onScreenWindows: () -> [CapturableWindow]
    /// True from the hotkey until the overlay is gone, so a second press cannot stack another overlay.
    private var isSelecting = false

    public convenience init() {
        self.init(
            service: ScreenCaptureKitService(), overlay: SelectionOverlayController(), recognizer: VisionTextRecognizer(),
            pasteboard: SystemPasteboard(), chip: SystemCaptureChipWindow(),
            makeEditors: { MarkupEditorWindowController(module: $0) },
            // Preflight only reads the grant; it never shows the system prompt.
            hasScreenAccess: { CGPreflightScreenCaptureAccess() },
            onScreenWindows: {
                CapturableWindow.parse(CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? [])
            },
            saveDirectory: { $0.standardDirectory },
            dragCopiesDirectory: Self.defaultDragCopiesDirectory
        )
    }

    /// Tests pass fakes, so they never touch ScreenCaptureKit, create panels or editor windows, ask for access or write a
    /// pasteboard.
    init(
        service: any CaptureService,
        overlay: any SelectionOverlay,
        recognizer: any TextRecognizing,
        pasteboard: any PasteboardWriting,
        chip: any CaptureChipPresenting,
        makeEditors: @escaping @MainActor (ScreenshotModule) -> any MarkupEditorHosting,
        hasScreenAccess: @escaping () -> Bool,
        onScreenWindows: @escaping () -> [CapturableWindow],
        saveDirectory: @escaping (SaveLocation) -> URL?,
        dragCopiesDirectory: URL
    ) {
        self.service = service
        self.overlay = overlay
        self.recognizer = recognizer
        self.pasteboard = pasteboard
        chipPresenter = chip
        self.makeEditors = makeEditors
        self.hasScreenAccess = hasScreenAccess
        self.onScreenWindows = onScreenWindows
        self.saveDirectory = saveDirectory
        self.dragCopiesDirectory = dragCopiesDirectory
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        do {
            try context.storage.ensureDirectories()
        } catch {
            throw .failed(reason: "Không tạo được thư mục lưu ảnh chụp")
        }
        try? FileManager.default.removeItem(at: dragCopiesDirectory)
        let store = CaptureStore(directory: context.storage.directory, cachesDirectory: context.storage.cachesDirectory, logger: context.logger)
        state.records = store.load()
        self.store = store
        self.context = context
        keys = ScreenshotSettingKeys(context.settings)
        chip = CaptureChipController(presenter: chipPresenter, scheduler: context.scheduler)
        context.hotkeys.register("capture", title: "Chụp màn hình", initial: Self.captureShortcut) { [weak self] in
            self?.beginCapture(.regionOrWindow)
        }
        context.hotkeys.register("ocr", title: "OCR vùng chọn", initial: Self.ocrShortcut) { [weak self] in
            self?.beginCapture(.ocrRegion)
        }
    }

    public func stop() async {
        overlay.cancel()
        chip?.hide()
        chip = nil
        editors?.closeAll()
        editors = nil
        ocrTask?.cancel()
        ocrTask = nil
        context = nil
        keys = nil
        store = nil
        state.records = []
    }

    public func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id, title: "Ảnh chụp", systemImage: "camera.viewfinder",
            preferredHeight: 200, content: AnyView(ScreenshotTabView(module: self))
        )
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        AnyView(ScreenshotSettingsView(settings: environment.settings, keys: ScreenshotSettingKeys(environment.settings)))
    }

    // MARK: Capture

    /// What the overlay's result turned into: pixels to keep, or a window still to capture on its own.
    private enum Selection {
        case image(CGImage, scale: CGFloat)
        case window(CGWindowID, scale: CGFloat)
    }

    /// The hotkeys' entry point. The work is cancelled with the module.
    private func beginCapture(_ mode: SelectionMode) {
        context?.run { [weak self] in await self?.capture(mode: mode) }
    }

    /// One capture from hotkey to tray, or to the clipboard for OCR. Ignored while an overlay is already up.
    func capture(mode: SelectionMode) async {
        guard let context, let keys, let store, !isSelecting else { return }
        guard hasScreenAccess() else {
            showPermissionHint()
            return
        }
        cancelOCR()
        // The chip is a window of its own: it has to be gone before the screens are frozen, or it would be in the capture.
        chip?.hide()
        let selection: Selection?
        do {
            selection = try await select(mode)
        } catch {
            if isCurrent(context) { report(error) }
            return
        }
        guard isCurrent(context), let selection else { return }
        let image: CGImage, scale: CGFloat
        switch selection {
        case .image(let selected, let selectedScale):
            (image, scale) = (selected, selectedScale)
        case .window(let id, let windowScale):
            do {
                image = try await service.captureWindow(id: id, includeShadow: context.settings.value(keys.windowShadow))
                scale = windowScale
            } catch {
                if isCurrent(context) { report(error) }
                return
            }
        }
        guard isCurrent(context) else { return }
        if mode == .ocrRegion {
            startOCR(image, feedback: .activity)
        } else {
            await keep(image, scale: scale, store: store, keys: keys, context: context)
        }
    }

    /// Freezes the screens, runs the overlay and turns its result into pixels. The frozen frames are released
    /// before this returns, so a window is captured and an image stored without them in memory.
    private func select(_ mode: SelectionMode) async throws -> Selection? {
        isSelecting = true
        defer { isSelecting = false }
        let frozen = try await service.freezeDisplays()
        guard !frozen.isEmpty else { throw CaptureError.noDisplays }
        let windows = onScreenWindows()
        guard let result = await overlay.run(mode: mode, frozen: frozen, windows: windows) else { return nil }
        switch result {
        case .region(let displayID, let pixelRect):
            guard let display = frozen.first(where: { $0.info.id == displayID }),
                  let cropped = display.image.detachedCrop(to: pixelRect) else { return nil }
            return .image(cropped, scale: display.info.scale)
        case .fullScreen(let displayID):
            guard let display = frozen.first(where: { $0.info.id == displayID }) else { return nil }
            return .image(display.image, scale: display.info.scale)
        case .window(let id):
            // Text is read from regions only; the overlay never offers windows then.
            guard mode != .ocrRegion else { return nil }
            return .window(id, scale: Self.scale(ofWindow: id, in: windows, displays: frozen.map(\.info)))
        }
    }

    /// The scale of the display a window is mostly on, which the PNG records as its DPI; the window's own capture
    /// has no scale to report.
    private static func scale(ofWindow id: CGWindowID, in windows: [CapturableWindow], displays: [DisplayInfo]) -> CGFloat {
        let primaryHeight = GeometryMapper.primaryHeight(of: displays) ?? 0
        let display = windows.first { $0.id == id }.flatMap {
            GeometryMapper.display(containingCenterOf: $0.bounds, in: displays, primaryHeight: primaryHeight)
        }
        return (display ?? displays.first)?.scale ?? 1
    }

    /// Stores the capture, copies it if asked and puts the chip beside it. A capture that cannot be stored is still copied.
    private func keep(_ image: CGImage, scale: CGFloat, store: CaptureStore, keys: ScreenshotSettingKeys, context: ModuleContext) async {
        var record: CaptureRecord?
        do {
            record = try await store.add(image, scale: scale, keepCount: context.settings.value(keys.keepCount))
            if isCurrent(context) { state.records = store.records }
        } catch {
            context.logger.error("Could not store a capture: \(error, privacy: .public)")
            showToast("Không lưu được ảnh chụp", systemImage: "exclamationmark.triangle.fill")
        }
        if context.settings.value(keys.copyToClipboard), !(await pasteboard.write(image, scale: scale)) {
            showToast("Không chép được ảnh", systemImage: "exclamationmark.triangle.fill")
        }
        guard let record, isCurrent(context), context.settings.value(keys.showCaptureChip) else { return }
        let thumbnail = await store.thumbnail(for: record.id, maxPixel: CaptureChipView.thumbnailMaxPixel)
        // Not while another capture has the screens: the chip is gone before they freeze and stays gone until it is done.
        guard isCurrent(context), !isSelecting else { return }
        // The buttons are the only way into the editor from here: nothing opens by itself.
        chip?.show(
            thumbnail: thumbnail,
            edit: { [weak self] in self?.context?.run { await self?.edit(record) } },
            copy: { [weak self] in self?.context?.run { await self?.copy(record) } }
        )
    }

    // MARK: OCR

    /// Where progress and results of text recognition show: beside the closed notch after a hotkey, as toasts
    /// when the tray is open, since activities stay hidden until the notch closes.
    enum Feedback {
        case activity, toast
    }

    /// Starts reading `image`, cancelling a recognition still running. Progress shows at once.
    func startOCR(_ image: CGImage, feedback: Feedback) {
        guard let context, let keys else { return }
        ocrTask?.cancel()
        let languages = context.settings.value(keys.ocrLanguages)
        announce(.recognizing, feedback: feedback)
        ocrTask = Task { [weak self] in
            await self?.recognize(image, languages: languages, feedback: feedback, context: context)
        }
    }

    private func recognize(_ image: CGImage, languages: [String], feedback: Feedback, context: ModuleContext) async {
        let text: String
        do {
            text = try await recognizer.recognize(image, languages: languages)
        } catch {
            guard !Task.isCancelled, isCurrent(context) else { return }
            context.logger.error("Text recognition failed: \(error, privacy: .public)")
            context.activities.clear(id: Self.ocrActivityID)
            showToast("Không nhận được chữ", systemImage: "exclamationmark.triangle.fill")
            return
        }
        // Cancelled recognitions are dropped: a newer capture owns the feedback now.
        guard !Task.isCancelled, isCurrent(context) else { return }
        if text.allSatisfy(\.isWhitespace) {
            announce(.noText, feedback: feedback)
        } else if pasteboard.write(text) {
            announce(.copied(characters: text.count), feedback: feedback)
        } else {
            context.activities.clear(id: Self.ocrActivityID)
            showToast("Không chép được văn bản", systemImage: "exclamationmark.triangle.fill")
        }
    }

    /// A new capture or a stop ends the recognition and takes its progress away.
    private func cancelOCR() {
        ocrTask?.cancel()
        ocrTask = nil
        context?.activities.clear(id: Self.ocrActivityID)
    }

    private static let ocrActivityID = "ocr"

    private func announce(_ message: OCRMessage, feedback: Feedback) {
        switch feedback {
        case .activity:
            context?.activities.set(LiveActivity(
                id: Self.ocrActivityID, expiresAfter: message == .recognizing ? nil : .seconds(3),
                leading: AnyView(ScreenshotActivityIcon(systemImage: message.systemImage)),
                trailing: AnyView(ScreenshotActivityText(text: message.text))
            ))
        case .toast:
            showToast(message.text, systemImage: message.systemImage, duration: message == .recognizing ? .seconds(1) : .seconds(2))
        }
    }

    // MARK: Feedback

    /// A short message; the only feedback visible while the tray is open.
    func showToast(_ text: String, systemImage: String, duration: Duration = .seconds(2)) {
        context?.presenter.showToast(AnyView(ScreenshotToast(text: text, systemImage: systemImage)), duration: duration)
    }

    private func showPermissionHint() {
        showToast(
            "Cần quyền Ghi màn hình: bật MyNotch trong Cài đặt hệ thống → Quyền riêng tư & Bảo mật",
            systemImage: "lock.rectangle.fill", duration: .seconds(5)
        )
    }

    private func report(_ error: any Error) {
        switch CaptureError(error) {
        case .permissionDenied:
            showPermissionHint()
        case .noDisplays:
            showToast("Không tìm thấy màn hình để chụp", systemImage: "display.trianglebadge.exclamationmark")
        case .failed(let reason):
            context?.logger.error("Capture failed: \(reason, privacy: .public)")
            showToast("Không chụp được màn hình", systemImage: "exclamationmark.triangle.fill")
        }
    }

    /// Work that outlived its run of the module (stopped, or stopped and started again) must not touch the new one.
    private func isCurrent(_ context: ModuleContext) -> Bool {
        self.context === context && !Task.isCancelled
    }
}
