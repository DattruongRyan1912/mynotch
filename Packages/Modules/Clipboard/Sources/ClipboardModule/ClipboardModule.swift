import AppKit
import MyNotchCore
import Observation
import SwiftUI

/// Clipboard history in the notch: records every copy, shows it in a tab and puts items back on request. A copy stack
/// collects copies while it is on and pastes them one by one.
public final class ClipboardModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "clipboard",
        displayName: "Clipboard",
        systemImage: "doc.on.clipboard",
        defaultEnabled: true,
        permissions: [],
        optionalPermissions: [.accessibility, .pasteboard],
        permissionReasons: [
            .accessibility: "Dán mục bạn chọn vào app đang dùng (giả lập ⌘V).",
            .pasteboard: "Ghi lại mọi lần chép mà macOS không hỏi lại.",
        ],
        order: 100
    )

    /// How long a ⌘V waits after a paste from the library window, whose keyboard focus has to return to the app
    /// behind it first (the notch needs 80 ms, but it closes at once).
    static let libraryPasteDelay: Duration = .milliseconds(250)

    let state = ClipboardState()
    /// Kept by the module so image cards do not decode their thumbnails again each time the notch opens. The library and the floating
    /// panel take handles on it (`ClipboardThumbnailCache(maxPixelSize:sharing:)`), so the three share one budget.
    let thumbnails = ClipboardThumbnailCache()
    /// Lets the thumbnails go when the system is short of memory, while the module runs.
    let memoryWatch = ClipboardMemoryWatch()
    /// The pictures of the open locked boards, which are in memory and in no file; see `ClipboardModule+Vault`.
    let openImages = ClipboardOpenImages()
    /// The editor windows that are open; see `ClipboardModule+Edit`.
    let editors = ClipboardEditors()
    /// Whether Touch ID can be offered, looked at once per run; nil until it is asked.
    var touchIDProbe: Bool?
    /// How long a drag's file stays after the drag is over, for the drop target to read it.
    static let dragCleanupDelay: Duration = .seconds(2)
    /// Set while the library window is open, and nil otherwise so a closed library costs nothing.
    private(set) var library: ClipboardLibraryModel?
    /// Set while the floating panel is open, and nil otherwise so a closed panel costs nothing.
    private(set) var panel: ClipboardPanelModel?
    /// Set while running; tests wait for its writes.
    private(set) var store: ClipboardStore?
    /// What Settings shows of the agents' access; it outlives the module's running.
    let mcp = ClipboardMCPState()
    let mcpSocketPath: (URL) -> String
    let installMCPHelper: (URL) throws -> Void
    /// Set while the feature is on and the module runs; see `ClipboardModule+MCP`.
    var mcpServer: ClipboardMCPServer?
    /// Set while running: the open locked boards and what closes them; see `ClipboardModule+Vault`.
    var vault: ClipboardVault?
    /// The optional sounds; see `ClipboardModule+Sound`. The clock is monotonic seconds.
    let soundPlayer: any ClipboardSoundPlaying
    let soundClock: () -> Double
    var soundGate = ClipboardSoundGate()
    /// Whether the paste that is on its way is one that makes no sound; see `notePasteForSound`.
    var pasteIsQuiet = true
    /// The optional link previews; see `ClipboardModule+LinkPreview`.
    let linkFetcher: ClipboardLinkFetcher
    let linkPreviews = ClipboardLinkFetches()
    /// How long a link's card stays on screen before its page is read; a test makes it longer or shorter.
    var linkPreviewDwell = ClipboardModule.defaultLinkPreviewDwell
    let keychain: any BoardKeyKeychain
    let authenticator: any UserAuthenticating
    let keyDerivation: ClipboardVaultCrypto.Derivation
    let lockTriggers: ClipboardLockTriggers
    private let pasteboard: any PasteboardAccess
    private let keystrokes: any KeystrokeSending
    private let frontmostApp: () -> ClipboardMonitor.SourceApp
    private let isTrusted: () -> Bool
    private let pasteboardAccessBehavior: () -> NSPasteboard.AccessBehavior
    private let modifiers: any ModifierState
    let now: () -> Date
    /// nil in tests that never show it; the app passes the real window.
    private let libraryWindow: (any ClipboardLibraryWindowing)?
    /// nil in tests that never show it; the app passes the real panel.
    private let panelWindow: (any ClipboardPanelWindowing)?
    /// The large preview of each of the windows that have one (Space, ⌘Y): the library, the floating panel and the notch's tab. Each has
    /// its own, so each closes only its own.
    private let libraryPreviewWindow: (any ClipboardPreviewWindowing)?
    private let panelPreviewWindow: (any ClipboardPreviewWindowing)?
    private let tabPreviewWindow: (any ClipboardPreviewWindowing)?
    /// The notch tab's large preview; it follows `state`, so it exists as long as the module does.
    let tabPreview: ClipboardTabPreviewModel
    private(set) var context: ModuleContext?
    private(set) var keys: ClipboardSettingKeys?
    private var monitor: ClipboardMonitor?
    private var paster: ClipboardPaster?
    /// Closed on stop, so a ⌘V still waiting for the paste delay is never sent into whatever app is in front by then.
    private var keystrokeGate: KeystrokeGate?
    /// How much text one step of the classification of old items looks at (what detection reads of each, at most 4 KB, so about
    /// 64 long texts), and the most items a step takes, which only matters for very short ones.
    static let classifyBatchBytes = 256 * 1024
    static let classifyBatchItems = 2_000
    /// The wait between two steps, which leaves the main actor to the window.
    static let classifyStepDelay: Duration = .milliseconds(25)

    /// The step that is being worked out in the background, nil before the first and after the last. Tests wait for it.
    private(set) var classification: Task<Void, Never>?
    /// The sizes of the steps taken so far, in items and in bytes looked at.
    private(set) var classificationBatches: [(items: Int, bytes: Int)] = []
    private var classificationStep: ScheduledAction?
    /// The last flush or file edit. Starts, flushes and edits wait for it, so two of them never touch the files at once.
    /// Not private so tests can queue work they control.
    var diskWork: Task<Void, Never>?
    /// The settings of the module as `start` or the Settings page last handed them over, kept after a stop: the Storage page's daily clean-up
    /// applies the retention rule to a module that is off. See `ClipboardModule+StorageCleaning`.
    var storageSettings: ModuleSettings?
    /// Where the rule is read from when `storageSettings` is nil (Clipboard off since launch, no Settings page shown yet): the app's own
    /// store, which holds the same keys. A test passes its own.
    lazy var storageFallbackSettings = SettingsStore(defaults: .standard)
    /// Told one line per clean of the Storage page: numbers only, never what was copied. A test reads them.
    var storageReport: (String) -> Void = { Log.logger(category: "clipboard").info("\($0, privacy: .public)") }
    /// Backups being written or restored. The Storage page's cleans do nothing while there are any: a backup reads the pictures of the history,
    /// and a restore stores pictures before it adds their items.
    var backupsInFlight = 0

    public convenience init() {
        self.init(
            pasteboard: SystemPasteboard(),
            keystrokes: CGEventKeystrokeSender(),
            frontmostApp: {
                let app = NSWorkspace.shared.frontmostApplication
                return (app?.bundleIdentifier, app?.localizedName)
            },
            isTrusted: { AXIsProcessTrusted() },
            // Reading the behavior does not read the pasteboard, so it never prompts.
            pasteboardAccessBehavior: { NSPasteboard.general.accessBehavior },
            modifiers: SystemModifierState(),
            libraryWindow: ClipboardLibraryWindowController(),
            panelWindow: ClipboardPanelController(),
            libraryPreview: ClipboardPreviewController(),
            panelPreview: ClipboardPreviewController(),
            tabPreview: ClipboardPreviewController(),
            soundPlayer: ClipboardSystemSoundPlayer(),
            linkTransport: ClipboardLinkNetwork()
        )
    }

    /// Tests pass fakes, so they never touch the system pasteboard or post key events.
    init(
        pasteboard: any PasteboardAccess,
        keystrokes: any KeystrokeSending,
        frontmostApp: @escaping () -> ClipboardMonitor.SourceApp,
        isTrusted: @escaping () -> Bool,
        pasteboardAccessBehavior: @escaping () -> NSPasteboard.AccessBehavior,
        modifiers: any ModifierState,
        now: @escaping () -> Date = { .now },
        libraryWindow: (any ClipboardLibraryWindowing)? = nil,
        panelWindow: (any ClipboardPanelWindowing)? = nil,
        libraryPreview: (any ClipboardPreviewWindowing)? = nil,
        panelPreview: (any ClipboardPreviewWindowing)? = nil,
        tabPreview: (any ClipboardPreviewWindowing)? = nil,
        mcpSocketPath: @escaping (URL) -> String = ClipboardModule.defaultMCPSocketPath,
        installMCPHelper: @escaping (URL) throws -> Void = ClipboardMCPHelperFile.installFromBundle,
        keychain: any BoardKeyKeychain = SystemBoardKeyKeychain(),
        authenticator: any UserAuthenticating = SystemUserAuthenticator(),
        keyDerivation: ClipboardVaultCrypto.Derivation = .standard,
        lockTriggers: ClipboardLockTriggers = .system,
        soundPlayer: any ClipboardSoundPlaying = ClipboardSilentPlayer(),
        soundClock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
        linkTransport: any ClipboardLinkTransport = ClipboardNoNetwork(),
        linkTimeouts: (request: Duration, total: Duration) = (ClipboardLinkFetcher.requestTimeout, ClipboardLinkFetcher.totalTimeout),
        linkSleep: @escaping ClipboardLinkFetcher.Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.soundPlayer = soundPlayer
        self.soundClock = soundClock
        linkFetcher = ClipboardLinkFetcher(
            transport: linkTransport, requestTimeout: linkTimeouts.request, totalTimeout: linkTimeouts.total, sleep: linkSleep
        )
        self.mcpSocketPath = mcpSocketPath
        self.installMCPHelper = installMCPHelper
        thumbnails.openImages = openImages
        self.keychain = keychain
        self.authenticator = authenticator
        self.keyDerivation = keyDerivation
        self.lockTriggers = lockTriggers
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.frontmostApp = frontmostApp
        self.isTrusted = isTrusted
        self.pasteboardAccessBehavior = pasteboardAccessBehavior
        self.modifiers = modifiers
        self.now = now
        self.libraryWindow = libraryWindow
        self.panelWindow = panelWindow
        libraryPreviewWindow = libraryPreview
        panelPreviewWindow = panelPreview
        tabPreviewWindow = tabPreview
        self.tabPreview = ClipboardTabPreviewModel(state: state)
        self.tabPreview.onActivate = { [weak self] item in self?.activate(item) }
        let tabModel = self.tabPreview
        attachPreview(to: tabModel, window: tabPreview) { tabModel.hostWindow() }
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        await finishDiskWork()
        do {
            try context.storage.ensureDirectories()
        } catch {
            throw .failed(reason: "Không tạo được thư mục lưu lịch sử clipboard")
        }
        let store = ClipboardStore(directory: context.storage.directory, scheduler: context.scheduler, logger: context.logger, now: now)
        let keys = ClipboardSettingKeys(context.settings)
        storageSettings = context.settings
        self.context = context
        self.keys = keys
        self.store = store
        classificationBatches = []
        thumbnails.logger = context.logger
        // Warning or critical alike: the pictures are decoded again as cards ask for them.
        memoryWatch.start { [weak self] _ in self?.thumbnails.releaseMemory() }

        let loaded = store.load()
        var history = loaded
        // Boards that have a vault are locked, whatever the history file still holds of them.
        let sealed = startVault(context, history: &history)
        // Images are deleted before the save that drops their items, so a crash in between leaves items without images.
        _ = history.remove(ids: Set(loaded.items.filter { !hasImageFile($0, in: store) }.map(\.id)))
        history.removeDanglingPins()
        let removed = prune(&history) + sealed
        state.history = history
        store.deleteImages(for: removed)
        if history.persistable != loaded { store.scheduleSave(history) }
        // A picture of a link that no item holds any more (an item gone while MyNotch was not running, a board that locked).
        store.deleteOrphanLinkPreviews(keeping: history.linkPreviewFileNames)
        refreshPasteboardAccess()
        refreshAccessibility()
        restoreStack(from: store, keys: keys, settings: context.settings, excluding: Set(sealed.map(\.id)))
        scheduleClassification()

        let keystrokeGate = KeystrokeGate(keystrokes)
        // Every ⌘V of a paste of ours goes through the gate, so this is the one place that knows it went out.
        keystrokeGate.onSent = { [weak self] in
            ClipboardPanelLog.record("⌘V sent")
            self?.playPasteSound()
        }
        self.keystrokeGate = keystrokeGate
        paster = ClipboardPaster(
            pasteboard: pasteboard, keystrokes: keystrokeGate, scheduler: context.scheduler, isTrusted: isTrusted, modifiers: modifiers
        )
        let settings = context.settings
        let monitor = ClipboardMonitor(
            pasteboard: pasteboard, scheduler: context.scheduler, frontmostApp: frontmostApp,
            shouldCapture: {
                (
                    paused: settings.value(keys.paused),
                    excluded: Set(settings.value(keys.excludedBundleIDs)),
                    classifier: ClipboardClassifier(
                        ignoreSensitive: settings.value(keys.ignoreSensitive), colorsWithoutHash: settings.value(keys.colorsWithoutHash)
                    )
                )
            },
            onCapture: { [weak self] content, imageData, source, isSensitive in
                self?.record(content, imageData: imageData, source: source, isSensitive: isSensitive)
            }
        )
        self.monitor = monitor
        monitor.start()

        context.hotkeys.register(
            "openClipboard", title: "Mở lịch sử clipboard", initial: KeyboardShortcuts.Shortcut(.v, modifiers: [.control, .option])
        ) { [weak self] in self?.openTab() }
        context.hotkeys.register(
            "openLibrary", title: "Mở thư viện clipboard",
            initial: KeyboardShortcuts.Shortcut(.v, modifiers: [.control, .option, .shift])
        ) { [weak self] in self?.openLibrary() }
        context.hotkeys.register(
            "openPanel", title: "Mở bảng clipboard nổi", initial: KeyboardShortcuts.Shortcut(.c, modifiers: [.command, .shift])
        ) { [weak self] in self?.togglePanel() }
        context.hotkeys.register(
            "toggleStack", title: "Bật hoặc tắt ngăn xếp clipboard",
            initial: KeyboardShortcuts.Shortcut(.c, modifiers: [.control, .option])
        ) { [weak self] in self?.toggleStack() }
        // Not ⌃⌥V, which already opens the history: two shortcuts on one combination would both fire.
        context.hotkeys.register(
            "pasteStack", title: "Dán mục kế tiếp trong ngăn xếp",
            initial: KeyboardShortcuts.Shortcut(.v, modifiers: [.control, .option, .command])
        ) { [weak self] in self?.pasteNextInStack() }
        context.run { [weak self] in
            // The first value arrives at once and prunes nothing new; later ones apply a changed limit right away.
            for await _ in Observations({ (settings.value(keys.historyLimit), settings.value(keys.retention), settings.value(keys.imageStorageLimitMB)) }) {
                self?.update { _ in [] }
            }
        }
        context.run { [weak self] in
            // On opens the socket for the agents' helper; off closes it. The first value arrives at once, and is off unless the
            // user turned it on in an earlier run.
            for await enabled in Observations({ settings.value(keys.mcpEnabled) }) {
                self?.applyMCP(enabled: enabled)
            }
        }
        context.run { [weak self] in
            // Turning link previews off stops the ones that are on their way; nothing more is read from then on.
            for await enabled in Observations({ settings.value(keys.linkPreviews) }) where !enabled {
                self?.cancelLinkFetches()
            }
        }
        context.run { [weak self] in
            // Keeping or not keeping the stack takes effect at once: the file is written, or deleted.
            for await _ in Observations({ settings.value(keys.stackPersist) }) {
                self?.writeStackFile()
            }
        }
    }

    /// Writes any unsaved change before returning, so quitting right after a copy keeps it.
    public func stop() async {
        cancelLinkFetches()
        stopMCP()
        // Every open board is sealed and closed first, so nothing of one outlives the module in memory or on disk.
        stopVault()
        saveEditorDraftsBeforeStopping()
        closeLibrary()
        closePanel()
        tabPreview.closePreview()
        tabPreviewWindow?.close()
        // A module that is off holds no pictures.
        memoryWatch.stop()
        thumbnails.removeAll()
        keystrokeGate?.isOpen = false
        keystrokeGate = nil
        classificationStep?.cancel()
        classificationStep = nil
        classification?.cancel()
        monitor?.stop()
        monitor = nil
        paster = nil
        context = nil
        keys = nil
        let store = store
        self.store = nil
        let previous = diskWork
        let flush = Task {
            await previous?.value
            await store?.flush()
        }
        diskWork = flush
        await flush.value
        state.reset()
    }

    public func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id, title: "Clipboard", systemImage: "doc.on.clipboard",
            preferredHeight: 230, acceptsKeyboard: true, content: AnyView(ClipboardTabView(module: self))
        )
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        let directory = environment.storage.directory
        storageSettings = environment.settings
        return AnyView(ClipboardSettingsView(
            settings: environment.settings,
            keys: ClipboardSettingKeys(environment.settings),
            usage: environment.isRunning ? .live(state) : .disk(directory),
            clear: { [weak self] range in await self?.clearHistory(range, directory: directory).value },
            pasteboardAccessBehavior: pasteboardAccessBehavior,
            canBackUp: environment.isRunning,
            mcp: ClipboardMCPActions(
                state: mcp, helperPath: ClipboardMCPHelperFile.destination(in: directory).path,
                copy: { text in
                    // Marked as MyNotch's own, so the history does not record the command the user just copied from it.
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    pasteboard.setData(Data(), forType: OwnPasteboardWrite.pasteboardType)
                },
                turnOff: { [weak self] in self?.turnOffMCPNow(settings: environment.settings) }
            ),
            // The module outlives its running, so a backup asked for after a stop says why it cannot be done.
            backupActions: ClipboardBackupActions(
                export: { [weak self] options, url, progress in
                    guard let self else { throw ClipboardBackupError.moduleStopped }
                    return try await self.exportBackup(options, to: url, progress: progress)
                },
                planRestore: { [weak self] url, progress in
                    guard let self else { throw ClipboardBackupError.moduleStopped }
                    return try await self.planRestore(from: url, progress: progress)
                },
                legacyTextCount: { [weak self] scope in
                    self.map { ClipboardBackupWriter.legacyTextCount(in: $0.backupHistory, scope: scope) } ?? 0
                },
                lockedBoardCount: { [weak self] in self?.protectedBoardIDs.count ?? 0 }
            )
        ))
    }

    public var menuItems: [ModuleMenuItem] {
        [ModuleMenuItem(id: "openLibrary", title: "Thư viện Clipboard…") { [weak self] in self?.openLibrary() }]
    }

    /// The ⌃⌥V shortcut.
    func openTab() {
        context?.presenter.open()
    }

    /// Opens the library window, or brings it forward when it is open. Does nothing while stopped. The library's
    /// model exists only while the window does.
    func openLibrary() {
        guard let context, let keys, store != nil, let libraryWindow else { return }
        if libraryWindow.isOpen {
            libraryWindow.bringToFront()
            return
        }
        let settings = context.settings
        let model = ClipboardLibraryModel(
            state: state, actions: self,
            preferences: ClipboardLibraryPreferences(
                layout: settings.value(keys.libraryLayout), sort: settings.value(keys.librarySort),
                cardSize: settings.value(keys.libraryCardSize), inspectorVisible: settings.value(keys.libraryInspectorVisible)
            ),
            thumbnails: ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize, sharing: thumbnails),
            now: now
        )
        model.onPreferencesChange = { preferences in
            settings.set(preferences.layout, for: keys.libraryLayout)
            settings.set(preferences.sort, for: keys.librarySort)
            settings.set(preferences.cardSize, for: keys.libraryCardSize)
            settings.set(preferences.inspectorVisible, for: keys.libraryInspectorVisible)
        }
        library = model
        attachPreview(to: model, window: libraryPreviewWindow) { [weak libraryWindow] in (libraryWindow?.frame, libraryWindow?.windowIdentity) }
        libraryWindow.show(AnyView(ClipboardLibraryView(module: self, model: model)), model: model, onClose: { [weak self] in
            self?.libraryClosed(model)
        })
    }

    /// The ⇧⌘C shortcut: opens the floating panel beside the pointer, or closes it when it is open. A pinned panel that
    /// lost the keyboard takes it back instead, since the shortcut then means "let me type there". Does nothing while
    /// stopped. The panel's model exists only while the panel does.
    func togglePanel() {
        guard let context, let keys, store != nil, let panelWindow else { return }
        if panelWindow.isOpen {
            if panel?.isPinned == true, !panelWindow.isKey {
                panelWindow.focus()
            } else {
                closePanel()
            }
            return
        }
        let settings = context.settings
        let pinned = settings.value(keys.panelPinned)
        let model = ClipboardPanelModel(
            state: state, actions: self, isPinned: pinned,
            thumbnails: ClipboardThumbnailCache(maxPixelSize: ClipboardThumbnailCache.libraryPixelSize, sharing: thumbnails), now: now
        )
        model.onClose = { [weak self] in self?.closePanel() }
        model.onReturnKeyboard = { [weak panelWindow] in panelWindow?.returnKeyboard() ?? false }
        model.isKeyboardBack = { [weak panelWindow] in panelWindow?.keyboardIsWithFrontApp() ?? false }
        model.onPinnedChange = { [weak self] pinned in self?.panelPinChanged(pinned) }
        model.onMove = { origin in settings.set(ClipboardPanelPosition(origin), for: keys.panelPosition) }
        model.panelFrame = { [weak panelWindow] in panelWindow?.frame }
        panel = model
        attachPreview(to: model, window: panelPreviewWindow) { [weak panelWindow] in (panelWindow?.frame, panelWindow?.windowIdentity) }
        // Only a pinned panel is where it was left; an unpinned one is always beside the pointer.
        let restoredOrigin = pinned ? settings.value(keys.panelPosition)?.point : nil
        panelWindow.show(AnyView(ClipboardPanelView(module: self, model: model)), model: model, restoringOrigin: restoredOrigin) { [weak self] in
            self?.panelClosed(model)
        }
    }

    /// A short message over the open tab, where activities stay hidden until the notch closes.
    func showToast(_ text: String, systemImage: String) {
        context?.presenter.showToast(AnyView(ClipboardToast(text: text, systemImage: systemImage)), duration: .milliseconds(1200))
    }

    /// Re-read when the tab or Settings appear, since the user changes it in System Settings.
    func refreshPasteboardAccess() {
        let denied = pasteboardAccessBehavior() == .alwaysDeny
        if state.pasteboardDenied != denied { state.pasteboardDenied = denied }
    }

    /// Whether a click would paste without the permission pasting needs. Reading trust never prompts. The tab and the
    /// library check when they appear and every 2 s while shown, so the hint goes by itself once it is granted.
    func refreshAccessibility() {
        var needs = false
        if let context, let keys {
            needs = context.settings.value(keys.clickAction) == .paste && !isTrusted()
        }
        if state.needsAccessibility != needs { state.needsAccessibility = needs }
    }

    /// The hint's button: the system's prompt (which lists MyNotch in the Accessibility pane), then that pane when the
    /// prompt alone did not allow it. nil while stopped; await the task for completion.
    @discardableResult
    func requestAccessibility() -> Task<Void, Never>? {
        guard let context else { return nil }
        return Task { [weak self] in
            if await context.permissions.request(.accessibility) != .granted {
                context.permissions.openSystemSettings(for: .accessibility)
            }
            self?.refreshAccessibility()
        }
    }

    // MARK: Actions used by the tab

    /// A click or Return on a card: the click action from Settings. What happened; nil while stopped.
    @discardableResult
    func activate(_ item: ClipboardItem) -> ClipboardPaster.Outcome? {
        guard let context, let keys else { return nil }
        return put(item, paste: context.settings.value(keys.clickAction) == .paste)
    }

    /// The floating panel's click action: the same, except that a paste first lets the panel get the keyboard out of the
    /// way. `beforePaste` runs after the pasteboard is written and before ⌘V is sent; when it answers false nothing is
    /// pasted, the item stays on the pasteboard, and a hint says to press ⌘V. nil while stopped.
    @discardableResult
    func activate(_ item: ClipboardItem, beforePaste: @escaping () -> Bool) -> ClipboardPaster.Outcome? {
        guard let context, let keys else { return nil }
        return put(item, paste: context.settings.value(keys.clickAction) == .paste, beforePaste: beforePaste)
    }

    @discardableResult
    func copy(_ item: ClipboardItem, plainText: Bool = false) -> ClipboardPaster.Outcome? {
        put(item, paste: false, plainTextOnly: plainText)
    }

    /// With `plainText`, the formatting of a rich text is left behind ("Dán dạng văn bản thường").
    @discardableResult
    func paste(_ item: ClipboardItem, plainText: Bool = false) -> ClipboardPaster.Outcome? {
        put(item, paste: true, plainTextOnly: plainText)
    }

    /// Records the transformed text as a new item (classified like a copy, so a decoded URL becomes a link) and copies it.
    /// Returns false when the transform does not apply to the item's text.
    @discardableResult
    func apply(_ transform: TextTransform, to item: ClipboardItem) -> Bool {
        guard let context, let keys, item.content.kind == .text, let text = item.content.plainText,
              let result = transform.apply(text) else { return false }
        let classifier = ClipboardClassifier(ignoreSensitive: false, colorsWithoutHash: context.settings.value(keys.colorsWithoutHash))
        let snapshot = PasteboardSnapshot(types: [NSPasteboard.PasteboardType.string.rawValue], string: result)
        guard case .content(let content, _) = classifier.classify(snapshot) else { return false }
        // The result of changing a secret of a locked board is as much a secret: it goes into the same board, and so is sealed with it.
        let lockedBoards = state.history.boards(containing: item.id).filter(\.isProtected).map(\.id)
        var addedID: UUID?
        update { history in
            let added = history.add(
                content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: now(), isSensitive: item.isSensitive
            ).id
            addedID = added
            for board in lockedBoards { history.pin(itemID: added, to: board) }
            return []
        }
        guard let added = state.history.items.first(where: { $0.id == addedID }) else { return false }
        put(added, paste: false)
        return true
    }

    func delete(_ item: ClipboardItem) {
        delete(ids: [item.id])
    }

    /// One change for all of them, so deleting a selection saves once.
    func delete(ids: Set<UUID>) {
        update { $0.remove(ids: ids) }
    }

    func clearHistory(_ range: ClipboardClearRange) {
        update { $0.clear(newerThan: range.cutoff(from: now())) }
    }

    /// From Settings, which also works while the module is stopped: then the files are edited directly, after the
    /// flush or edit before it and before the next start reads them. Await the returned task for completion.
    @discardableResult
    func clearHistory(_ range: ClipboardClearRange, directory: URL) -> Task<Void, Never> {
        if store != nil {
            clearHistory(range)
            return Task {}
        }
        let previous = diskWork
        let work = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            // A start that got in first owns the files now.
            if self.store != nil {
                self.clearHistory(range)
            } else {
                await self.clearFiles(range, directory: directory)
            }
        }
        diskWork = work
        return work
    }

    /// nil for an empty name or while stopped.
    @discardableResult
    func createBoard(named name: String) -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard store != nil, !name.isEmpty else { return nil }
        var boardID: UUID?
        update { history in
            boardID = history.createBoard(name: name)
            return []
        }
        return boardID
    }

    func renameBoard(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        update { history in
            history.renameBoard(id: id, name: name)
            return []
        }
    }

    func deleteBoard(_ id: UUID) {
        // A board that has a lock takes its items, its vault file and its key with it.
        if let board = state.history.boards.first(where: { $0.id == id }), board.isProtected {
            deleteProtectedBoard(board)
            return
        }
        update { history in
            history.deleteBoard(id: id)
            return []
        }
    }

    /// Ignores a name that is not a symbol name, which only a bug could send.
    func setBoardIcon(_ id: UUID, to systemImage: String) {
        guard ClipboardBoardIcon.isValidName(systemImage) else { return }
        update { history in
            history.setBoardIcon(id: id, systemImage: systemImage)
            return []
        }
    }

    func setBoardColor(_ id: UUID, to color: ClipboardBoardColor) {
        update { history in
            history.setBoardColor(id: id, color: color)
            return []
        }
    }

    /// Puts the board at `index` of the row, where the notch's and the library's boards show it.
    func moveBoard(_ id: UUID, to index: Int) {
        update { history in
            history.moveBoard(id: id, to: index)
            return []
        }
    }

    /// A step along the row, for the menus and VoiceOver.
    func moveBoard(_ id: UUID, by offset: Int) {
        update { history in
            history.moveBoard(id: id, by: offset)
            return []
        }
    }

    func pin(_ item: ClipboardItem, to boardID: UUID) {
        update { history in
            history.pin(itemID: item.id, to: boardID)
            return []
        }
        noteActivity(onBoard: boardID, pinned: [item.id])
    }

    /// `ids` in the order the library shows them, which the board then lists too (the newest pin goes first).
    func pin(ids: [UUID], to boardID: UUID) {
        update { history in
            for id in ids.reversed() { history.pin(itemID: id, to: boardID) }
            return []
        }
        noteActivity(onBoard: boardID, pinned: ids)
    }

    func unpin(_ item: ClipboardItem, from boardID: UUID) {
        update { history in
            history.unpin(itemID: item.id, from: boardID)
            return []
        }
        noteActivity(onBoard: boardID)
    }

    /// Working with an open locked board keeps it open: the idle time starts again. What was just pinned to it is a secret now: it
    /// leaves the copy stack, whose file would otherwise keep it in the clear.
    private func noteActivity(onBoard boardID: UUID, pinned: [UUID] = []) {
        guard state.history.boards.first(where: { $0.id == boardID })?.lock?.isUnlocked == true else { return }
        noteVaultActivity()
        let ids = Set(pinned)
        if !ids.isEmpty {
            updateStack { $0.removeEntries { ids.contains($0.item.id) } }
            adoptPictures(ids, into: boardID)
        }
    }

    func revealInFinder(_ item: ClipboardItem) {
        let urls = fileURLs(of: item)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func openLink(_ item: ClipboardItem) {
        guard let url = Self.openableLink(of: item) else { return }
        NSWorkspace.shared.open(url)
    }

    /// The image's stored PNG or the copied files; empty for other kinds.
    func fileURLs(of item: ClipboardItem) -> [URL] {
        switch item.content {
        // A picture of an open locked board is in memory and no file: there is nothing to reveal or to hand over.
        case .image(let image): openImages.contains(image.fileName) ? [] : store?.imageURL(fileName: image.fileName).map { [$0] } ?? []
        case .files(let urls): urls
        case .text, .richText, .link, .color: []
        }
    }

    /// Only web and mail links: `history.json` may have been edited to hold any URL, and opening one can launch apps.
    static func openableLink(of item: ClipboardItem) -> URL? {
        guard case .link(let url) = item.content, ["http", "https", "mailto"].contains(url.scheme?.lowercased()) else { return nil }
        return url
    }

    /// What dragging a card out carries. A stored image is dragged as a copy, or not at all when copying fails: a drop
    /// must never move or rename the stored file.
    func dragProvider(for item: ClipboardItem) -> NSItemProvider {
        // A card or row may be older than the history: an item of a board that has locked since (its items left memory), or one that
        // was deleted, carries nothing, whatever the view still holds of it.
        guard let item = state.history.items.first(where: { $0.id == item.id }) else { return NSItemProvider() }
        // A picture of an open locked board becomes a file only if the drop target asks, and only for the drag.
        if let provider = openImageDragProvider(for: item) { return provider }
        var urls = fileURLs(of: item)
        if case .image = item.content {
            urls = urls.prefix(1).compactMap { try? ClipboardDragProvider.copyImage(at: $0, copiedAt: item.copiedAt) }
        }
        return ClipboardDragProvider.make(for: item.content, fileURLs: urls)
    }

    // MARK: Copy stack

    /// The ⌃⌥C shortcut and the stack buttons: starts a stack, or stops the one that is on.
    func toggleStack() {
        if state.stack.isOn { stopStack() } else { startStack() }
    }

    /// Does nothing while stopped or when a stack is already on, which keeps what it holds.
    func startStack() {
        updateStack { $0.start() }
    }

    /// Ends the stack and forgets what it held. Says so beside the notch, since the shortcut works from any app.
    func stopStack() {
        let wasOn = state.stack.isOn
        updateStack { $0.stop() }
        if wasOn { announceStack("Đã tắt ngăn xếp", short: "Tắt") }
    }

    func removeFromStack(_ id: UUID) {
        updateStack { $0.remove(id: id) }
    }

    /// `source` and `destination` as a list's drag reports them.
    func moveInStack(from source: IndexSet, to destination: Int) {
        updateStack { $0.move(fromOffsets: source, toOffset: destination) }
    }

    /// Empties the stack and leaves it on.
    func clearStack() {
        updateStack { $0.clear() }
    }

    /// Which copy comes next, as the setting says; the list marks it.
    var stackOrder: CopyStackOrder {
        guard let context, let keys else { return .firstIn }
        return context.settings.value(keys.stackOrder)
    }

    /// The ⌃⌥⌘V shortcut: pastes the next item into the app in front, through the same checked path as the floating panel
    /// (the keyboard must be with that app, or the item is only copied and the stack stays where it was). ⌘V also waits
    /// until the shortcut's own keys are up, and the item leaves the stack only when ⌘V went out: when the keys stay down
    /// for a second the item is only copied, like any paste that cannot be done. An image whose file is gone is dropped
    /// first, with a note. An empty stack turns itself off, and a stack that is off says so instead of pasting.
    func pasteNextInStack() {
        guard let context, let keys, let store else { return }
        guard state.stack.isOn else {
            announceStack("Ngăn xếp đang tắt", short: "Tắt")
            return
        }
        let order = context.settings.value(keys.stackOrder)
        var dropped = 0
        var next = state.stack.next(order)
        while let entry = next, !hasImageFile(entry.item, in: store) {
            updateStack { $0.remove(id: entry.id) }
            dropped += 1
            next = state.stack.next(order)
        }
        guard let entry = next else {
            updateStack { $0.stop() }
            announceStack("Ngăn xếp đã hết", short: "Hết")
            return
        }
        if dropped > 0 { announceStack("Đã bỏ \(dropped) mục không còn trên đĩa", short: "−\(dropped)") }
        // The history keeps its order: pasting a run of copies must not turn it upside down.
        put(
            entry.item, paste: true, touchesHistory: false,
            beforePaste: { [weak self] in self?.keyboardIsReadyForStackPaste() ?? false },
            afterKeysUp: { [weak self] in self?.updateStack { $0.remove(id: entry.id) } }
        )
    }

    // MARK: Private

    /// Called by the library window closing, whether the user closed it or the module did.
    private func libraryClosed(_ model: ClipboardLibraryModel) {
        model.detach()
        // The pictures only the library needed go with it.
        model.thumbnails.release()
        libraryPreviewWindow?.close()
        if library === model { library = nil }
    }

    /// Shows the preview in `window` while `host` has it open, over the display of the host window's frame, and takes it away when the
    /// host closes it or the user clicks anywhere but on it. `hostWindow()` is the host window's frame and identity, asked for each time
    /// it opens. The window is told nothing else: what it draws follows the host.
    private func attachPreview(
        to host: some ClipboardPreviewHosting, window: (any ClipboardPreviewWindowing)?, hostWindow: @escaping () -> (frame: CGRect?, id: ObjectIdentifier?)
    ) {
        guard let window else { return }
        host.onPreviewChange = { [weak self, weak host, weak window] open in
            guard open, let self, let host else {
                window?.close()
                return
            }
            let hostWindow = hostWindow()
            window?.show(AnyView(ClipboardPreviewView(host: host, module: self)), hostFrame: hostWindow.frame, hostWindow: hostWindow.id) { [weak host] in
                host?.closePreview()
            }
        }
    }

    /// The panel was pinned or unpinned: remembered for the next time, along with where it is when pinned.
    private func panelPinChanged(_ pinned: Bool) {
        guard let context, let keys else { return }
        context.settings.set(pinned, for: keys.panelPinned)
        if pinned, let origin = panelWindow?.origin { context.settings.set(ClipboardPanelPosition(origin), for: keys.panelPosition) }
    }

    /// Called by the panel window closing, whether the user closed it or the module did.
    private func panelClosed(_ model: ClipboardPanelModel) {
        model.detach()
        model.thumbnails.release()
        panelPreviewWindow?.close()
        if panel === model { panel = nil }
    }

    private func closePanel() {
        panelWindow?.close()
        if let panel { panelClosed(panel) }
    }

    private func closeLibrary() {
        libraryWindow?.close()
        if let library { libraryClosed(library) }
    }

    /// Called by the monitor for each new copy.
    private func record(_ content: ClipboardContent, imageData: Data?, source: ClipboardMonitor.SourceApp, isSensitive: Bool) {
        guard let context, let keys, let store else { return }
        // The same picture as one in an open locked board is that board's: it is not written to disk.
        if let imageData, case .image(let image) = content, !openImages.contains(image.fileName) {
            do {
                try store.saveImage(imageData, fileName: image.fileName)
            } catch {
                // An item whose image is missing could never be shown or pasted.
                let nsError = error as NSError
                context.logger.error("Saving a copied image failed (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))")
                return
            }
        }
        var addedID: UUID?
        update { history in
            addedID = history.add(content, hash: ClipboardContent.hash(of: content), source: source, at: now(), isSensitive: isSensitive).id
            return []
        }
        playCaptureSound(for: addedID)
        // A secret never goes on the stack, even when the history is set to keep it, and neither does an item of a locked board.
        if state.stack.isOn, !isSensitive, let added = state.history.items.first(where: { $0.id == addedID }),
           !state.history.protectedItemIDs.contains(added.id) {
            updateStack { $0.collect(added) }
        }
        if context.settings.value(keys.showCopiedActivity) {
            context.activities.set(LiveActivity(
                id: "copied", expiresAfter: .milliseconds(1500),
                leading: AnyView(ClipboardActivityIcon(systemImage: "doc.on.clipboard.fill")),
                trailing: AnyView(ClipboardActivityIcon(systemImage: content.kind.systemImage))
            ))
        }
    }

    // MARK: Old items

    /// Texts saved before code detection existed are classified a batch at a time: the scheduler starts a step, the batch is
    /// worked out on a background task (about a millisecond for a 4 KB text, so up to 256 KB takes tens of milliseconds, none of
    /// it on the main actor), and the answers are applied in one change that costs a pass over the history. Nothing is
    /// scheduled when there is nothing to do, and a copy made meanwhile keeps its own answer.
    private func scheduleClassification() {
        guard let context, !state.history.unclassifiedTexts(maxBytes: 1, maxItems: 1).isEmpty else { return }
        classificationStep = context.scheduler.schedule(after: Self.classifyStepDelay) { [weak self] in
            self?.classifyNextBatch()
        }
    }

    private func classifyNextBatch() {
        let batch = state.history.unclassifiedTexts(maxBytes: Self.classifyBatchBytes, maxItems: Self.classifyBatchItems)
        guard !batch.isEmpty else {
            classification = nil
            return
        }
        classificationBatches.append((batch.count, batch.reduce(0) { $0 + min($1.text.utf8.count, ClipboardCodeDetector.sampleBytes) }))
        classification = Task { [weak self] in
            let answers = await Task.detached(priority: .utility) {
                batch.map { ($0.id, ClipboardCodeDetector.detect(text: $0.text)) }
            }.value
            guard let self, !Task.isCancelled, store != nil else { return }
            update { history in
                history.applyDetections(answers)
                return []
            }
            scheduleClassification()
        }
    }

    /// Puts the item on the pasteboard and moves it to the top. A paste always closes the notch, at once, so keyboard focus
    /// is back in the previous app before ⌘V is sent; a copy closes it when "close after action" is on. A failed write changes nothing and keeps the notch open. A paste from the library window hands the keyboard
    /// back to the app behind it and waits longer for that before sending ⌘V. `beforePaste` is the floating panel's way to
    /// get the keyboard out of its own window between the write and ⌘V; a refusal pastes nothing and asks the user to
    /// press ⌘V. `touchesHistory` is off for the stack, whose pastes must not reorder the history. `afterKeysUp` is the
    /// shortcut's: ⌘V waits for the user's keys, and it runs when ⌘V went out.
    @discardableResult
    private func put(
        _ item: ClipboardItem, paste: Bool, plainTextOnly: Bool = false, touchesHistory: Bool = true,
        beforePaste: (() -> Bool)? = nil, afterKeysUp: (() -> Void)? = nil
    ) -> ClipboardPaster.Outcome? {
        guard let context, let keys, let paster else { return nil }
        let fromLibrary = paste && libraryWindow?.isFrontmost == true
        // Remembers a refusal, which comes back as a plain `.copied`.
        var keyboardRefused = false
        let outcome = paster.perform(
            item, imageURL: imageURL(of: item), imageData: openImages.data(for: item), paste: paste, plainTextOnly: plainTextOnly,
            delay: fromLibrary ? Self.libraryPasteDelay : nil,
            beforePaste: beforePaste.map { ask in
                {
                    let isBack = ask()
                    if !isBack { keyboardRefused = true }
                    return isBack
                }
            },
            // A shortcut's paste waits for its keys to be up, and tells when ⌘V is really out or given up.
            afterKeysUp: afterKeysUp.map { sent in
                ClipboardPaster.KeyRelease(onSent: sent, onTimeout: { [weak self] in self?.pasteTimedOut() })
            }
        )
        notePasteForSound(of: item)
        let closeAfterAction = context.settings.value(keys.closeAfterAction)
        switch outcome {
        case .pasted:
            if beforePaste != nil { ClipboardPanelLog.record("panel paste: ⌘V is on its way") }
            context.presenter.close()
        case .copiedNeedsPermission:
            ClipboardPanelLog.record("paste not sent, no Accessibility permission: hint to press ⌘V")
            askToPressPaste(context)
        case .copied:
            // The keyboard did not leave the panel, so nothing was pasted: the user pastes by hand, as without Accessibility.
            if keyboardRefused {
                ClipboardPanelLog.record("panel paste refused, the keyboard did not leave the panel: hint to press ⌘V")
                askToPressPaste(context)
            } else if closeAfterAction {
                context.presenter.close()
            }
        case .failed:
            // The notch stays open, where only a toast is visible.
            context.presenter.showToast(
                AnyView(ClipboardToast(text: "Không chép được mục này", systemImage: "exclamationmark.triangle.fill")),
                duration: .seconds(2)
            )
            return outcome
        }
        if fromLibrary { libraryWindow?.yieldKeyboardFocus() }
        // Using an item of an open locked board keeps the board open.
        if state.history.protectedItemIDs.contains(item.id) { noteVaultActivity() }
        if touchesHistory {
            update { history in
                history.touch(id: item.id, at: now())
                return []
            }
        }
        return outcome
    }

    /// The item is on the pasteboard but was not pasted: closes the notch like a paste, since the user pastes into the
    /// previous app, and tells them so beside it (activities show only beside the closed notch).
    private func askToPressPaste(_ context: ModuleContext) {
        context.presenter.close()
        context.activities.set(LiveActivity(
            id: "pasteHint", expiresAfter: .seconds(3),
            leading: AnyView(ClipboardActivityIcon(systemImage: "doc.on.clipboard.fill")),
            trailing: AnyView(ClipboardPasteKeyHint())
        ))
        // A newcomer no longer takes the notch from an activity of the same priority that is already live (the
        // "copied" one, or music), but the user has to see this one to know ⌘V is theirs to press.
        context.activities.raise(id: "pasteHint")
    }

    /// The keys that asked for a paste stayed down, so nothing was sent: the item is on the pasteboard for the user's ⌘V.
    private func pasteTimedOut() {
        guard let context else { return }
        askToPressPaste(context)
    }

    /// Whether a ⌘V now would reach the app in front. A floating panel that is open hands the keyboard back first (a
    /// pinned one stays on screen); with none open it is only a check. Without a panel window, nothing is known: no.
    private func keyboardIsReadyForStackPaste() -> Bool {
        guard let panelWindow else { return false }
        return panelWindow.isOpen ? panelWindow.returnKeyboard() : panelWindow.keyboardIsWithFrontApp()
    }

    /// Applies a change to the stack, then brings the live activity and the file on disk up to date. Does nothing while
    /// stopped or when the change leaves the stack as it was.
    func updateStack(_ change: (inout CopyStack) -> Void) {
        guard let context, let keys, store != nil else { return }
        var stack = state.stack
        change(&stack)
        guard stack != state.stack else { return }
        state.stack = stack
        refreshStackActivity()
        if context.settings.value(keys.stackPersist) { writeStackFile() }
    }

    /// While the stack is on, a live activity beside the notch counts what it holds; its summary is the whole sentence,
    /// since the 64 pt beside the notch only fit the number.
    private func refreshStackActivity() {
        guard let context else { return }
        let count = state.stack.entries.count
        guard state.stack.isOn else {
            context.activities.clear(id: "stack")
            return
        }
        context.activities.set(LiveActivity(
            id: "stack",
            leading: AnyView(ClipboardActivityIcon(systemImage: "square.stack.3d.up.fill")),
            trailing: AnyView(ClipboardStackActivityText(text: "\(count)")),
            // With music or another activity in front, the stack is a bubble the size of the notch: the count still fits.
            minimal: AnyView(ClipboardStackBubbleCount(count: count)),
            summary: "Ngăn xếp: \(count) mục"
        ))
    }

    /// A few seconds beside the notch for what a shortcut pressed in another app did, or could not do.
    private func announceStack(_ text: String, short: String) {
        guard let context else { return }
        context.activities.set(LiveActivity(
            id: "stackNotice", expiresAfter: .seconds(2),
            leading: AnyView(ClipboardActivityIcon(systemImage: "square.stack.3d.up")),
            trailing: AnyView(ClipboardStackActivityText(text: short)),
            summary: text
        ))
        // The user has to see it to know why nothing was pasted, even with music or another notice live.
        context.activities.raise(id: "stackNotice")
    }

    /// A kept stack comes back, without the images whose file is gone. Then the file is made to agree with the setting,
    /// so a stack file from a time the user kept stacks does not linger once they stopped.
    private func restoreStack(from store: ClipboardStore, keys: ClipboardSettingKeys, settings: ModuleSettings, excluding sealed: Set<UUID>) {
        if settings.value(keys.stackPersist), var restored = store.loadStack() {
            restored.removeEntries { !hasImageFile($0.item, in: store) }
            // An item of a locked board that a crash left in the stack file does not come back with it.
            restored.removeEntries { sealed.contains($0.item.id) || state.history.protectedItemIDs.contains($0.item.id) }
            state.stack = restored
        }
        writeStackFile()
        refreshStackActivity()
    }

    /// Writes the stack when the user keeps stacks between launches and one is on; deletes the file otherwise.
    private func writeStackFile() {
        guard let context, let keys, let store else { return }
        let keep = context.settings.value(keys.stackPersist) && state.stack.isOn
        store.saveStack(keep ? state.stack : nil)
    }

    /// The picture's file, for the pasteboard; nil for a picture held in memory, which is written from its bytes.
    private func imageURL(of item: ClipboardItem) -> URL? {
        guard case .image(let image) = item.content, !openImages.contains(image.fileName) else { return nil }
        return store?.imageURL(fileName: image.fileName)
    }

    /// What a card, a row or a thumbnail is given to draw the picture from: its file, or for a picture of an open locked board a URL
    /// that names no file and that the thumbnail cache reads from memory. nil for any other item.
    func displayImageURL(of item: ClipboardItem) -> URL? {
        guard case .image(let image) = item.content else { return nil }
        if openImages.contains(image.fileName) { return ClipboardOpenImages.url(forFileName: image.fileName) }
        return store?.imageURL(fileName: image.fileName)
    }

    /// Where the preview reads an image item's picture from: the bytes of one in an open locked board (which are in no file), or its
    /// stored file. nil for any other item, or while stopped.
    func previewImageSource(of item: ClipboardItem) -> ClipboardPreviewImageSource? {
        guard case .image(let image) = item.content else { return nil }
        if let data = openImages.data(forFileName: image.fileName) { return .memory(data) }
        return store?.imageURL(fileName: image.fileName).map { .file($0) }
    }

    func hasImageFile(_ item: ClipboardItem, in store: ClipboardStore) -> Bool {
        guard case .image(let image) = item.content else { return true }
        if openImages.contains(image.fileName) { return true }
        guard let url = store.imageURL(fileName: image.fileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Waits for the queued disk work, including work queued while waiting.
    private func finishDiskWork() async {
        while let work = diskWork {
            await work.value
            if diskWork == work { diskWork = nil }
        }
    }

    /// Clears a stopped module's files. Images are deleted only once the history that no longer lists them is
    /// written, so a failed write loses nothing.
    private func clearFiles(_ range: ClipboardClearRange, directory: URL) async {
        // A module that never ran has nothing to clear, and Settings must not create its folder.
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        let store = ClipboardStore(directory: directory, scheduler: TaskScheduler(), logger: Log.logger(category: descriptor.id.rawValue), now: now)
        var history = store.load()
        history.removeDanglingPins()
        let removed = history.clear(newerThan: range.cutoff(from: now()))
        guard !removed.isEmpty else { return }
        store.scheduleSave(history)
        await store.flush()
        if store.writeCount > 0 {
            store.deleteImages(for: removed)
            store.deleteLinkPreviewImages(named: removed.compactMap(\.linkPreviewFileName))
        }
    }

    /// Applies a change, enforces the limits, deletes the images of removed items and schedules a save.
    /// `change` returns the items it removed. Does nothing while stopped.
    func update(_ change: (inout ClipboardHistory) -> [ClipboardItem]) {
        guard let store else { return }
        var history = state.history
        let removed = change(&history) + prune(&history)
        guard history != state.history else { return }
        let previewFiles = state.history.linkPreviewFileNames
        state.history = history
        store.deleteImages(for: removed)
        store.scheduleSave(history)
        deleteStaleLinkPreviews(of: previewFiles)
        vaultHistoryChanged()
    }

    /// The limits in Settings as they are now; nil while stopped.
    var pruneLimits: ClipboardRestoreImpact.Limits? {
        guard let context, let keys else { return nil }
        let settings = context.settings
        return ClipboardRestoreImpact.Limits(
            limit: settings.value(keys.historyLimit), retention: settings.value(keys.retention),
            imageByteLimit: settings.value(keys.imageStorageLimitMB) * ClipboardStorageUsage.bytesPerMB
        )
    }

    /// Removes items beyond the limits in Settings; returns them so their images can be deleted.
    func prune(_ history: inout ClipboardHistory) -> [ClipboardItem] {
        guard let limits = pruneLimits else { return [] }
        return history.prune(limit: limits.limit, retention: limits.retention, imageByteLimit: limits.imageByteLimit, now: now())
    }
}

/// Passes ⌘V on until closed; the paster keeps its sender, so this is how a stop drops a paste still waiting.
private final class KeystrokeGate: KeystrokeSending {
    var isOpen = true
    /// Told after each ⌘V that went out, and only then: a closed gate sends nothing and says nothing.
    var onSent: (() -> Void)?
    private let sender: any KeystrokeSending

    init(_ sender: any KeystrokeSending) {
        self.sender = sender
    }

    func sendPaste() {
        guard isOpen else { return }
        sender.sendPaste()
        onSent?()
    }
}
