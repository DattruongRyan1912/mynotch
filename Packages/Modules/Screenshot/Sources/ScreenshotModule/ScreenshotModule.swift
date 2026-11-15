import AppKit
import MyNotchCore
import NotchUI
import SwiftUI

/// Screenshots in the notch: a hotkey freezes the screens, the overlay picks a region, window or display, and the
/// result goes to the tray, optionally the clipboard, and a chip with "Sửa" and "Chép" beside it. A second hotkey reads
/// the text of a region instead (OCR). The same overlay picks what to record, and `RecordingCoordinator` makes the recording.
public final class ScreenshotModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "screenshot",
        displayName: "Ảnh chụp",
        systemImage: "camera.viewfinder",
        defaultEnabled: true,
        permissions: [.screenRecording],
        // Only the folder the "Lưu vào" setting points at is written; Pictures needs no permission. Recording works without the
        // microphone (it is switched off in the settings) and without Accessibility (only the mouse is noticed).
        optionalPermissions: [.microphone, .accessibility, .desktopFolder, .downloadsFolder],
        permissionReasons: [
            .screenRecording: "Chụp và quay màn hình.",
            .microphone: "Quay màn hình kèm tiếng nói của bạn.",
            .accessibility: "Biết lúc bạn gõ phím khi quay, để zoom không thu về giữa câu. MyNotch không ghi phím nào, chỉ ghi thời điểm.",
            .desktopFolder: "Lưu ảnh vào Desktop (nơi lưu mặc định của “Lưu vào”).",
            .downloadsFolder: "Lưu ảnh vào Downloads khi chọn nơi lưu là Downloads.",
        ],
        order: 300
    )

    static let captureShortcut = KeyboardShortcuts.Shortcut(.s, modifiers: [.control, .option])
    static let ocrShortcut = KeyboardShortcuts.Shortcut(.o, modifiers: [.control, .option])
    static let pickColorShortcut = KeyboardShortcuts.Shortcut(.one, modifiers: [.command, .shift])
    static let pinCaptureShortcut = KeyboardShortcuts.Shortcut(.two, modifiers: [.command, .shift])
    static let recordShortcut = KeyboardShortcuts.Shortcut(.r, modifiers: [.control, .option])
    static let recordPauseShortcut = KeyboardShortcuts.Shortcut(.r, modifiers: [.control, .option, .shift])
    static let scrollingCaptureShortcut = KeyboardShortcuts.Shortcut(.s, modifiers: [.control, .option, .shift])
    static let scrollingCaptureActivityID = "scrolling-capture"

    let state = ScreenshotState()
    /// Set while running.
    private(set) var store: CaptureStore?
    /// The text recognition in progress or just finished; a new capture cancels it. Tests wait for it.
    private(set) var ocrTask: Task<Void, Never>?
    private(set) var scrollingSession: ScrollingCaptureSession?
    private var scrollSamplingTask: Task<Void, Never>?
    private var scrollTailTask: Task<Void, Never>?
    let scrollingPreview: any ScrollingPreviewPresenting
    let pasteboard: any PasteboardWriting
    let recognizer: any TextRecognizing
    public let subjectLifter: any SubjectLifting
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
    let service: any CaptureService
    let overlay: any SelectionOverlay
    let colorPicker: any ColorPickerOverlay
    let pinnedWindows: any PinnedWindowManaging
    let hasScreenAccess: () -> Bool
    let onScreenWindows: () -> [CapturableWindow]
    /// True from the hotkey until the overlay is gone, so a second press cannot stack another overlay.
    var isSelecting = false
    /// What recording gets from the system; tests give fakes.
    let recordingDependencies: RecordingDependencies
    /// Makes the recordings; set while running.
    private(set) var recording: RecordingCoordinator?
    /// The settings `start` or the Settings page gave, kept for the storage page, which asks for the clean-up rules whether or not
    /// the module runs.
    var storageSettings: ModuleSettings?
    /// Where the clean-up rules are read from when `storageSettings` is nil: the app's own store, which a module that was off since
    /// launch has not been given yet. Tests give their own, so none reads the user's.
    let storageFallbackSettings: SettingsStore
    /// One line for each clean, made of numbers only; by default it goes to the log. Tests read it.
    var storageReport: (String) -> Void = { Log.logger(category: "screenshot").info("\($0, privacy: .public)") }
    private var markupObserver: (any NSObjectProtocol)?

    public convenience init() {
        self.init(
            service: ScreenCaptureKitService(), overlay: SelectionOverlayController(), colorPicker: ColorPickerOverlayController(), pinnedWindows: PinnedWindowManager(), recognizer: VisionTextRecognizer(),
            pasteboard: SystemPasteboard(), chip: SystemCaptureChipWindow(),
            makeEditors: { MarkupEditorWindowController(module: $0) },
            // Preflight only reads the grant; it never shows the system prompt.
            hasScreenAccess: { CGPreflightScreenCaptureAccess() },
            onScreenWindows: {
                CapturableWindow.parse(CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? [])
            },
            saveDirectory: { $0.standardDirectory },
            dragCopiesDirectory: Self.defaultDragCopiesDirectory,
            recording: .live,
            storageFallbackSettings: SettingsStore(defaults: .standard)
        )
    }

    /// Tests pass fakes, so they never touch ScreenCaptureKit, create panels or editor windows, ask for access, record, open a
    /// microphone, write a pasteboard or read the user's settings. Nothing here has a default for that reason.
    init(
        service: any CaptureService,
        overlay: any SelectionOverlay,
        colorPicker: any ColorPickerOverlay = ColorPickerOverlayController(),
        pinnedWindows: any PinnedWindowManaging = PinnedWindowManager(),
        recognizer: any TextRecognizing,
        subjectLifter: any SubjectLifting = VisionSubjectLifter(),
        pasteboard: any PasteboardWriting,
        chip: any CaptureChipPresenting,
        scrollingPreview: any ScrollingPreviewPresenting = SystemScrollingPreviewWindow(),
        makeEditors: @escaping @MainActor (ScreenshotModule) -> any MarkupEditorHosting,
        hasScreenAccess: @escaping () -> Bool,
        onScreenWindows: @escaping () -> [CapturableWindow],
        saveDirectory: @escaping (SaveLocation) -> URL?,
        dragCopiesDirectory: URL,
        recording: RecordingDependencies,
        storageFallbackSettings: SettingsStore
    ) {
        self.service = service
        self.overlay = overlay
        self.colorPicker = colorPicker
        self.pinnedWindows = pinnedWindows
        self.recognizer = recognizer
        self.subjectLifter = subjectLifter
        self.pasteboard = pasteboard
        chipPresenter = chip
        self.scrollingPreview = scrollingPreview
        self.makeEditors = makeEditors
        self.hasScreenAccess = hasScreenAccess
        self.onScreenWindows = onScreenWindows
        self.saveDirectory = saveDirectory
        self.dragCopiesDirectory = dragCopiesDirectory
        recordingDependencies = recording
        self.storageFallbackSettings = storageFallbackSettings
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
        let keys = ScreenshotSettingKeys(context.settings)
        self.keys = keys
        state.isMicrophoneEnabled = context.settings.value(keys.recordMicrophone) != MicrophoneChoice.off
        storageSettings = context.settings
        chip = CaptureChipController(presenter: chipPresenter, scheduler: context.scheduler)
        context.hotkeys.register("capture", title: "Chụp màn hình", initial: Self.captureShortcut) { [weak self] in
            self?.beginCapture(.regionOrWindow)
        }
        context.hotkeys.register("ocr", title: "OCR vùng chọn", initial: Self.ocrShortcut) { [weak self] in
            self?.beginCapture(.ocrRegion)
        }
        context.hotkeys.register("pickColor", title: "Chọn màu màn hình", initial: Self.pickColorShortcut) { [weak self] in
            self?.beginPickColor()
        }
        context.hotkeys.register("pinCapture", title: "Chụp và ghim lên màn hình", initial: Self.pinCaptureShortcut) { [weak self] in
            self?.beginPinCapture()
        }
        context.hotkeys.register("scrollingCapture", title: "Chụp cuộn dài", initial: Self.scrollingCaptureShortcut) { [weak self] in
            guard let self else { return }
            if scrollingSession != nil {
                Task { await self.finishScrollingCapture() }
            } else {
                beginScrollingCapture()
            }
        }
        let recordings = RecordingCoordinator(
            module: self, context: context, keys: keys, state: state,
            store: RecordingStore(root: context.storage.directory.appending(path: "Recordings", directoryHint: .isDirectory)),
            dependencies: recordingDependencies
        )
        recording = recordings
        context.hotkeys.register("record", title: "Quay màn hình hoặc dừng quay", initial: Self.recordShortcut) { [weak recordings] in
            recordings?.toggleFromShortcut()
        }
        context.hotkeys.register("recordPause", title: "Tạm dừng hoặc tiếp tục quay", initial: Self.recordPauseShortcut) { [weak recordings] in
            recordings?.pauseFromShortcut()
        }
        // Also what finds a recording that a crash cut short and rescues it.
        context.run { [weak recordings] in await recordings?.refreshList() }
        markupObserver = NotificationCenter.default.addObserver(
            forName: .openMarkupEditorForImage, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let url = notification.object as? URL
            let data = notification.object as? Data
            Task { @MainActor in
                if let url {
                    await self.openEditorForImage(url: url)
                } else if let data {
                    await self.openEditorForImageData(data)
                }
            }
        }
    }

    public func stop() async {
        if let markupObserver { NotificationCenter.default.removeObserver(markupObserver) }
        self.markupObserver = nil
        overlay.cancel()
        colorPicker.cancel()
        pinnedWindows.closeAll()
        // A recording is closed properly, and kept; the editors of recordings close with it.
        await recording?.shutdown()
        recording = nil
        chip?.hide()
        chip = nil
        editors?.closeAll()
        editors = nil
        ocrTask?.cancel()
        ocrTask = nil
        cancelScrollingCapture()
        cancelSubjectLift()
        context = nil
        keys = nil
        store = nil
        state.records = []
        state.recordings = []
    }

    /// Stop and pause while a recording is made, for when the notch is hidden; the menu asks each time it opens.
    public var menuItems: [ModuleMenuItem] { recording?.menuItems ?? [] }

    public func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id, title: "Ảnh chụp", systemImage: "camera.viewfinder",
            preferredHeight: 200, content: AnyView(ScreenshotTabView(module: self))
        )
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        storageSettings = environment.settings
        return AnyView(ScreenshotSettingsView(settings: environment.settings, keys: ScreenshotSettingKeys(environment.settings)))
    }

    // MARK: Capture

    /// What the overlay's result turned into: pixels to keep, or a window still to capture on its own.
    private enum Selection {
        case image(CGImage, scale: CGFloat, sourceFrame: CGRect?, target: ScrollingTarget?)
        case window(CGWindowID, scale: CGFloat, sourceFrame: CGRect?)
    }

    /// The hotkeys' entry point. The work is cancelled with the module.
    private func beginCapture(_ mode: SelectionMode) {
        context?.run { [weak self] in await self?.capture(mode: mode) }
    }

    /// Entry point for "Chụp và ghim lên màn hình" (⇧⌘2).
    public func beginPinCapture() {
        guard let context, !isSelecting, recording?.phase != .selecting else { return }
        guard hasScreenAccess() else {
            showPermissionHint()
            return
        }
        chip?.hide()
        context.run { [weak self] in
            await self?.captureAndPin()
        }
    }

    private func captureAndPin() async {
        guard let context, let keys, let store, !isSelecting, recording?.phase != .selecting else { return }
        guard hasScreenAccess() else {
            showPermissionHint()
            return
        }
        cancelOCR()
        chip?.hide()
        let selection: Selection?
        do {
            selection = try await select(.regionOrWindow)
        } catch {
            if isCurrent(context) { report(error) }
            return
        }
        guard isCurrent(context), let selection else { return }
        let image: CGImage, scale: CGFloat, sourceFrame: CGRect?
        switch selection {
        case .image(let selected, let selectedScale, let frame, _):
            (image, scale, sourceFrame) = (selected, selectedScale, frame)
        case .window(let id, let windowScale, let frame):
            do {
                image = try await service.captureWindow(id: id, includeShadow: context.settings.value(keys.windowShadow))
                scale = windowScale
                sourceFrame = frame
            } catch {
                if isCurrent(context) { report(error) }
                return
            }
        }
        guard isCurrent(context) else { return }
        var record: CaptureRecord?
        do {
            record = try await store.add(image, scale: scale, keepCount: context.settings.value(keys.keepCount))
            if isCurrent(context) { state.records = store.records }
        } catch {
            context.logger.error("Could not store a capture: \(error, privacy: .public)")
        }
        if context.settings.value(keys.copyToClipboard), !(await pasteboard.write(image, scale: scale)) {
            showToast("Không chép được ảnh", systemImage: "exclamationmark.triangle.fill")
        }
        let editAction: (@MainActor () -> Void)?
        let saveAsAction: (@MainActor () -> Void)?
        if let record {
            editAction = { [weak self] in
                Task { await self?.edit(record) }
            }
            saveAsAction = { [weak self] in
                Task { await self?.saveAs(record) }
            }
        } else {
            editAction = nil
            saveAsAction = nil
        }
        let actions = PinnedWindowActions(
            copy: { [weak self] in
                if let record {
                    Task { await self?.copy(record) }
                } else {
                    Task { [weak self] in
                        guard let self else { return }
                        let ok = await pasteboard.write(image, scale: scale)
                        if ok {
                            context.activities.set(LiveActivity(
                                id: "copy-pin",
                                expiresAfter: .seconds(3),
                                leading: AnyView(Image(systemName: "doc.on.clipboard.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(NotchTokens.primaryText)),
                                trailing: AnyView(ScreenshotActivityText(text: "Đã chép ảnh"))
                            ))
                        }
                    }
                }
            },
            ocr: { [weak self] in
                self?.startOCR(image, feedback: .activity)
            },
            liftSubject: { [weak self] in
                self?.startSubjectLift(image, scale: scale, feedback: .activity)
            },
            edit: editAction,
            saveAs: saveAsAction
        )
        pinnedWindows.pin(
            image: image,
            scale: scale,
            record: record,
            sourceFrame: sourceFrame,
            actions: actions
        )
    }

    /// Entry point for Pick Color shortcut (⇧⌘1).
    public func beginPickColor() {
        guard let context, !isSelecting, recording?.phase != .selecting else { return }
        guard hasScreenAccess() else {
            showPermissionHint()
            return
        }
        chip?.hide()
        context.run { [weak self] in
            await self?.pickColor()
        }
    }

    private func pickColor() async {
        guard let context, let keys else { return }
        isSelecting = true
        defer { isSelecting = false }

        let frozen: [FrozenDisplay]
        do {
            frozen = try await service.freezeDisplays()
        } catch {
            if isCurrent(context) { report(error) }
            return
        }
        guard !frozen.isEmpty else {
            if isCurrent(context) { report(CaptureError.noDisplays) }
            return
        }

        let initialFormat = context.settings.value(keys.colorFormat)
        let result = await colorPicker.run(
            frozen: frozen,
            initialFormat: initialFormat
        ) { [weak context, keys] newFormat in
            context?.settings.set(newFormat, for: keys.colorFormat)
        }

        guard isCurrent(context), let result else { return }

        context.settings.set(result.format, for: keys.colorFormat)

        let copied = pasteboard.write(result.clipboardText)
        if copied {
            let label = result.colors.count == 1 ? result.clipboardText : "\(result.colors.count) mã màu"
            context.activities.set(LiveActivity(
                id: "pick-color",
                expiresAfter: .seconds(3),
                leading: AnyView(Image(systemName: "eyedropper.halffull").font(.system(size: 14, weight: .semibold)).foregroundStyle(NotchTokens.primaryText)),
                trailing: AnyView(ScreenshotActivityText(text: "Đã chép \(label)"))
            ))
        } else {
            showToast("Không chép được mã màu", systemImage: "exclamationmark.triangle.fill")
        }
    }

    // MARK: - Scrolling Capture

    public func beginScrollingCapture() {
        guard let context, !isSelecting, recording?.phase != .selecting else { return }
        guard hasScreenAccess() else {
            showPermissionHint()
            return
        }
        chip?.hide()
        context.run { [weak self] in
            await self?.startScrollingCapture()
        }
    }

    func startScrollingCapture() async {
        guard let context, !isSelecting, recording?.phase != .selecting else { return }
        guard hasScreenAccess() else {
            showPermissionHint()
            return
        }
        cancelOCR()
        chip?.hide()

        let selection: Selection?
        do {
            selection = try await select(.regionOrWindow)
        } catch {
            if isCurrent(context) { report(error) }
            return
        }
        guard isCurrent(context), let selection else { return }

        let target: ScrollingTarget
        let initialImage: CGImage
        let scale: CGFloat
        let sourceFrame: CGRect?

        switch selection {
        case .image(let selected, let selectedScale, let frame, let scrollingTarget):
            guard let scrollingTarget else { return }
            target = scrollingTarget
            initialImage = selected
            scale = selectedScale
            sourceFrame = frame
        case .window(let id, let windowScale, let frame):
            target = .window(id: id)
            do {
                initialImage = try await service.captureWindow(id: id, includeShadow: false)
                scale = windowScale
                sourceFrame = frame
            } catch {
                if isCurrent(context) { report(error) }
                return
            }
        }

        guard isCurrent(context) else { return }

        let session = ScrollingCaptureSession(
            target: target,
            scale: scale,
            initialFrame: initialImage
        )
        self.scrollingSession = session
        state.isScrollingCaptureActive = true
        state.scrollingCaptureHeight = initialImage.height

        scrollingPreview.show(
            canvas: initialImage,
            frameCount: 1,
            avoidingRect: sourceFrame,
            onFinish: { [weak self] in Task { await self?.finishScrollingCapture() } },
            onCancel: { [weak self] in self?.cancelScrollingCapture() }
        )

        let gMon = NSEvent.addGlobalMonitorForEvents(matching: [.scrollWheel, .keyDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if event.type == .keyDown {
                    if event.keyCode == 36 || event.keyCode == 76 { // Return / Enter
                        await self.finishScrollingCapture()
                        return
                    } else if event.keyCode == 53 { // Escape
                        self.cancelScrollingCapture()
                        return
                    }
                }
                self.triggerScrollStep()
            }
        }
        if let gMon { session.eventMonitors.append(gMon) }

        let lMon = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown]) { [weak self] event in
            if event.type == .keyDown {
                if event.keyCode == 36 || event.keyCode == 76 {
                    Task { @MainActor [weak self] in await self?.finishScrollingCapture() }
                    return nil
                } else if event.keyCode == 53 {
                    Task { @MainActor [weak self] in self?.cancelScrollingCapture() }
                    return nil
                }
            }
            self?.triggerScrollStep()
            return event
        }
        if let lMon { session.eventMonitors.append(lMon) }

        context.activities.set(LiveActivity(
            id: Self.scrollingCaptureActivityID,
            expiresAfter: nil,
            leading: AnyView(ScreenshotSpinnerView()),
            trailing: AnyView(ScreenshotActivityText(text: "Cuộn để chụp (\(initialImage.height)px) • ⏎ để xong"))
        ))
    }

    func stepScrollingCapture() async -> LongCaptureStitcher.StitchOutcome? {
        guard let session = scrollingSession, !session.isSampling else { return nil }
        session.isSampling = true
        defer { session.isSampling = false }

        let nextFrame: CGImage
        switch session.target {
        case .region(let displayID, let pixelRect):
            do {
                let frozen = try await service.freezeDisplays()
                guard let display = frozen.first(where: { $0.info.id == displayID }),
                      let cropped = display.image.detachedCrop(to: pixelRect) else {
                    return nil
                }
                nextFrame = cropped
            } catch {
                return nil
            }
        case .window(let id):
            do {
                nextFrame = try await service.captureWindow(id: id, includeShadow: false)
            } catch {
                return nil
            }
        }

        let outcome = session.stitcher.append(nextFrame)
        switch outcome {
        case .appended(_, let newTotalHeight):
            session.frameCount += 1
            state.scrollingCaptureHeight = newTotalHeight
            scrollingPreview.update(canvas: session.stitcher.canvas, frameCount: session.frameCount)
            context?.activities.set(LiveActivity(
                id: Self.scrollingCaptureActivityID,
                expiresAfter: nil,
                leading: AnyView(ScreenshotSpinnerView()),
                trailing: AnyView(ScreenshotActivityText(text: "Cuộn để chụp (\(newTotalHeight)px) • ⏎ để xong"))
            ))
        case .reachedMaxHeight:
            Task { await self.finishScrollingCapture() }
        case .unchanged, .noOverlap:
            break
        }
        return outcome
    }

    public func finishScrollingCapture() async {
        scrollSamplingTask?.cancel()
        scrollSamplingTask = nil
        scrollTailTask?.cancel()
        scrollTailTask = nil
        scrollingPreview.hide()
        guard let session = scrollingSession else { return }
        session.cleanUp()
        self.scrollingSession = nil
        state.isScrollingCaptureActive = false
        state.scrollingCaptureHeight = 0

        let image = session.stitcher.canvas
        let scale = session.scale

        guard let context, let store, let keys else { return }
        await keep(image, scale: scale, sourceFrame: nil, store: store, keys: keys, context: context)

        context.activities.set(LiveActivity(
            id: Self.scrollingCaptureActivityID,
            expiresAfter: .seconds(3),
            leading: AnyView(Image(systemName: "rectangle.stack.badge.person.crop.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(NotchTokens.accent)),
            trailing: AnyView(ScreenshotActivityText(text: "Đã chụp cuộn (\(image.height)px)"))
        ))
    }

    public func cancelScrollingCapture() {
        scrollSamplingTask?.cancel()
        scrollSamplingTask = nil
        scrollTailTask?.cancel()
        scrollTailTask = nil
        scrollingPreview.hide()
        guard let session = scrollingSession else { return }
        session.cleanUp()
        self.scrollingSession = nil
        state.isScrollingCaptureActive = false
        state.scrollingCaptureHeight = 0
        context?.activities.clear(id: Self.scrollingCaptureActivityID)
    }

    private func triggerScrollStep() {
        guard let session = scrollingSession else { return }
        session.hasPendingScroll = true
        if !session.isSampling {
            startSamplingLoop()
        }
        scheduleTailSample()
    }

    private func startSamplingLoop() {
        guard let session = scrollingSession, !session.isSampling else { return }
        scrollSamplingTask?.cancel()
        scrollSamplingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while let session = self.scrollingSession, session.hasPendingScroll, !Task.isCancelled {
                session.hasPendingScroll = false
                let elapsed = session.lastSampleTime.duration(to: .now)
                let minInterval = Duration.milliseconds(55)
                if elapsed < minInterval {
                    try? await Task.sleep(for: minInterval - elapsed)
                }
                guard !Task.isCancelled, self.scrollingSession === session else { break }
                session.lastSampleTime = .now
                _ = await self.stepScrollingCapture()
            }
        }
    }

    private func scheduleTailSample() {
        scrollTailTask?.cancel()
        scrollTailTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled, let self, let session = self.scrollingSession else { return }
            if !session.isSampling {
                session.hasPendingScroll = false
                session.lastSampleTime = .now
                _ = await self.stepScrollingCapture()
            }
        }
    }

    /// One capture from hotkey to tray, or to the clipboard for OCR. Ignored while an overlay is already up.
    func capture(mode: SelectionMode) async {
        // Not while a recording is being set up either: it may be waiting for an answer about the microphone, before its overlay.
        guard let context, let keys, let store, !isSelecting, recording?.phase != .selecting else { return }
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
        let image: CGImage, scale: CGFloat, sourceFrame: CGRect?
        switch selection {
        case .image(let selected, let selectedScale, let frame, _):
            (image, scale, sourceFrame) = (selected, selectedScale, frame)
        case .window(let id, let windowScale, let frame):
            do {
                image = try await service.captureWindow(id: id, includeShadow: context.settings.value(keys.windowShadow))
                scale = windowScale
                sourceFrame = frame
            } catch {
                if isCurrent(context) { report(error) }
                return
            }
        }
        guard isCurrent(context) else { return }
        if mode == .ocrRegion {
            startOCR(image, feedback: .activity)
        } else {
            await keep(image, scale: scale, sourceFrame: sourceFrame, store: store, keys: keys, context: context)
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
            let sourceFrame = CGRect(
                x: display.info.frame.minX + pixelRect.minX / display.info.scale,
                y: display.info.frame.maxY - pixelRect.maxY / display.info.scale,
                width: pixelRect.width / display.info.scale,
                height: pixelRect.height / display.info.scale
            )
            return .image(
                cropped,
                scale: display.info.scale,
                sourceFrame: sourceFrame,
                target: .region(displayID: displayID, pixelRect: pixelRect)
            )
        case .fullScreen(let displayID):
            guard let display = frozen.first(where: { $0.info.id == displayID }) else { return nil }
            let fullRect = CGRect(x: 0, y: 0, width: display.image.width, height: display.image.height)
            return .image(
                display.image,
                scale: display.info.scale,
                sourceFrame: display.info.frame,
                target: .region(displayID: displayID, pixelRect: fullRect)
            )
        case .window(let id):
            // Text is read from regions only; the overlay never offers windows then.
            guard mode != .ocrRegion else { return nil }
            let primaryHeight = GeometryMapper.primaryHeight(of: frozen.map(\.info)) ?? 0
            let windowBounds = windows.first(where: { $0.id == id })?.bounds ?? .zero
            let sourceFrame = GeometryMapper.appKitRect(fromCG: windowBounds, primaryHeight: primaryHeight)
            return .window(id, scale: Self.scale(ofWindow: id, in: windows, displays: frozen.map(\.info)), sourceFrame: sourceFrame)
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
    private func keep(
        _ image: CGImage,
        scale: CGFloat,
        sourceFrame: CGRect?,
        store: CaptureStore,
        keys: ScreenshotSettingKeys,
        context: ModuleContext
    ) async {
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
        guard let record, isCurrent(context) else { return }
        if context.settings.value(keys.autoOpenEditor) {
            await edit(record)
            return
        }
        guard context.settings.value(keys.showCaptureChip) else { return }
        let thumbnail = await store.thumbnail(for: record.id, maxPixel: CaptureChipView.thumbnailMaxPixel)
        // Not while another capture has the screens: the chip is gone before they freeze and stays gone until it is done.
        guard isCurrent(context), !isSelecting else { return }
        chip?.show(
            thumbnail: thumbnail,
            edit: { [weak self] in self?.context?.run { await self?.edit(record) } },
            copy: { [weak self] in self?.context?.run { await self?.copy(record) } },
            pin: { [weak self] in self?.context?.run { await self?.pin(record, sourceFrame: sourceFrame) } }
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
    func cancelOCR() {
        ocrTask?.cancel()
        ocrTask = nil
        context?.activities.clear(id: Self.ocrActivityID)
    }

    private static let ocrActivityID = "ocr"

    // MARK: Subject Lifting

    private(set) var subjectLiftTask: Task<Void, Never>?
    private static let subjectLiftActivityID = "subject-lift"

    /// Starts lifting the foreground subject from `image`, cancelling any lift still running.
    func startSubjectLift(_ image: CGImage, scale: CGFloat = 2.0, feedback: Feedback) {
        guard let context else { return }
        subjectLiftTask?.cancel()
        announceSubjectLift(.lifting, feedback: feedback)
        subjectLiftTask = Task { [weak self] in
            await self?.performSubjectLift(image, scale: scale, feedback: feedback, context: context)
        }
    }

    private func performSubjectLift(_ image: CGImage, scale: CGFloat, feedback: Feedback, context: ModuleContext) async {
        let lifted: CGImage?
        do {
            lifted = try await subjectLifter.liftSubject(from: image, cropToSubject: true)
        } catch {
            guard !Task.isCancelled, isCurrent(context) else { return }
            context.logger.error("Subject lift failed: \(error, privacy: .public)")
            context.activities.clear(id: Self.subjectLiftActivityID)
            announceSubjectLift(.failed, feedback: feedback)
            return
        }

        guard !Task.isCancelled, isCurrent(context) else { return }
        guard let lifted else {
            announceSubjectLift(.noSubject, feedback: feedback)
            return
        }

        // Add to store so it appears in the tray as a new transparent capture
        if let store, let keys {
            do {
                _ = try await store.add(lifted, scale: scale, keepCount: context.settings.value(keys.keepCount))
                if isCurrent(context) { state.records = store.records }
            } catch {
                context.logger.error("Could not store lifted subject: \(error, privacy: .public)")
            }
        }

        // Write PNG with transparency to pasteboard
        _ = await pasteboard.write(lifted, scale: scale)
        announceSubjectLift(.lifted, feedback: feedback)
    }

    func cancelSubjectLift() {
        subjectLiftTask?.cancel()
        subjectLiftTask = nil
        context?.activities.clear(id: Self.subjectLiftActivityID)
    }

    func announceSubjectLift(_ message: SubjectLiftMessage, feedback: Feedback) {
        switch feedback {
        case .activity:
            context?.activities.set(LiveActivity(
                id: Self.subjectLiftActivityID,
                expiresAfter: message.isProcessing ? nil : .seconds(3),
                leading: AnyView(ScreenshotActivityIcon(systemImage: message.systemImage, isProcessing: message.isProcessing)),
                trailing: AnyView(ScreenshotActivityText(text: message.text))
            ))
        case .toast:
            showToast(
                message.text,
                systemImage: message.systemImage,
                isProcessing: message.isProcessing,
                duration: message.isProcessing ? .seconds(30) : .seconds(2)
            )
        }
    }

    func announce(_ message: OCRMessage, feedback: Feedback) {
        switch feedback {
        case .activity:
            context?.activities.set(LiveActivity(
                id: Self.ocrActivityID,
                expiresAfter: message.isProcessing ? nil : .seconds(3),
                leading: AnyView(ScreenshotActivityIcon(systemImage: message.systemImage, isProcessing: message.isProcessing)),
                trailing: AnyView(ScreenshotActivityText(text: message.text))
            ))
        case .toast:
            showToast(
                message.text,
                systemImage: message.systemImage,
                isProcessing: message.isProcessing,
                duration: message.isProcessing ? .seconds(30) : .seconds(2)
            )
        }
    }

    func toggleMicrophone() {
        guard let context, let keys else { return }
        let current = context.settings.value(keys.recordMicrophone)
        let newChoice = current == MicrophoneChoice.off ? MicrophoneChoice.systemDefault : MicrophoneChoice.off
        context.settings.set(newChoice, for: keys.recordMicrophone)
        state.isMicrophoneEnabled = newChoice != MicrophoneChoice.off
        showToast(state.isMicrophoneEnabled ? "Đã bật micro" : "Đã tắt micro", systemImage: state.isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill")
    }

    // MARK: Feedback

    /// A short message; the only feedback visible while the tray is open.
    func showToast(_ text: String, systemImage: String, isProcessing: Bool = false, duration: Duration = .seconds(2)) {
        context?.presenter.showToast(
            AnyView(ScreenshotToast(text: text, systemImage: systemImage, isProcessing: isProcessing)),
            duration: duration
        )
    }

    func showPermissionHint() {
        showToast(
            "Cần quyền Ghi màn hình: bật MyNotch trong Cài đặt hệ thống → Quyền riêng tư & Bảo mật",
            systemImage: "lock.rectangle.fill", duration: .seconds(5)
        )
    }

    func report(_ error: any Error) {
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
    func isCurrent(_ context: ModuleContext) -> Bool {
        self.context === context && !Task.isCancelled
    }
}
