import AppKit
import MyNotchCore
import Observation
import SwiftUI

/// Clipboard history in the notch: records every copy, shows it in a tab and puts items back on request.
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
    /// Kept by the module so image cards do not decode their thumbnails again each time the notch opens.
    let thumbnails = ClipboardThumbnailCache()
    /// Set while the library window is open, and nil otherwise so a closed library costs nothing.
    private(set) var library: ClipboardLibraryModel?
    /// Set while running; tests wait for its writes.
    private(set) var store: ClipboardStore?
    private let pasteboard: any PasteboardAccess
    private let keystrokes: any KeystrokeSending
    private let frontmostApp: () -> ClipboardMonitor.SourceApp
    private let isTrusted: () -> Bool
    private let pasteboardAccessBehavior: () -> NSPasteboard.AccessBehavior
    private let now: () -> Date
    /// nil in tests that never show it; the app passes the real window.
    private let libraryWindow: (any ClipboardLibraryWindowing)?
    private var context: ModuleContext?
    private var keys: ClipboardSettingKeys?
    private var monitor: ClipboardMonitor?
    private var paster: ClipboardPaster?
    /// Closed on stop, so a ⌘V still waiting for the paste delay is never sent into whatever app is in front by then.
    private var keystrokeGate: KeystrokeGate?
    /// The last flush or file edit. Starts, flushes and edits wait for it, so two of them never touch the files at once.
    /// Not private so tests can queue work they control.
    var diskWork: Task<Void, Never>?

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
            libraryWindow: ClipboardLibraryWindowController()
        )
    }

    /// Tests pass fakes, so they never touch the system pasteboard or post key events.
    init(
        pasteboard: any PasteboardAccess,
        keystrokes: any KeystrokeSending,
        frontmostApp: @escaping () -> ClipboardMonitor.SourceApp,
        isTrusted: @escaping () -> Bool,
        pasteboardAccessBehavior: @escaping () -> NSPasteboard.AccessBehavior,
        now: @escaping () -> Date = { .now },
        libraryWindow: (any ClipboardLibraryWindowing)? = nil
    ) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.frontmostApp = frontmostApp
        self.isTrusted = isTrusted
        self.pasteboardAccessBehavior = pasteboardAccessBehavior
        self.now = now
        self.libraryWindow = libraryWindow
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
        self.context = context
        self.keys = keys
        self.store = store

        let loaded = store.load()
        var history = loaded
        // Images are deleted before the save that drops their items, so a crash in between leaves items without images.
        _ = history.remove(ids: Set(loaded.items.filter { !hasImageFile($0, in: store) }.map(\.id)))
        history.removeDanglingPins()
        let removed = prune(&history)
        state.history = history
        store.deleteImages(for: removed)
        if history != loaded { store.scheduleSave(history) }
        refreshPasteboardAccess()
        refreshAccessibility()

        let keystrokeGate = KeystrokeGate(keystrokes)
        self.keystrokeGate = keystrokeGate
        paster = ClipboardPaster(pasteboard: pasteboard, keystrokes: keystrokeGate, scheduler: context.scheduler, isTrusted: isTrusted)
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
            onCapture: { [weak self] content, imageData, source in self?.record(content, imageData: imageData, source: source) }
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
        context.run { [weak self] in
            // The first value arrives at once and prunes nothing new; later ones apply a changed limit right away.
            for await _ in Observations({ (settings.value(keys.historyLimit), settings.value(keys.retention), settings.value(keys.imageStorageLimitMB)) }) {
                self?.update { _ in [] }
            }
        }
    }

    /// Writes any unsaved change before returning, so quitting right after a copy keeps it.
    public func stop() async {
        closeLibrary()
        keystrokeGate?.isOpen = false
        keystrokeGate = nil
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
        return AnyView(ClipboardSettingsView(
            settings: environment.settings,
            keys: ClipboardSettingKeys(environment.settings),
            usage: environment.isRunning ? .live(state) : .disk(directory),
            clear: { [weak self] range in await self?.clearHistory(range, directory: directory).value },
            pasteboardAccessBehavior: pasteboardAccessBehavior
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
                cardSize: settings.value(keys.libraryCardSize)
            ),
            now: now
        )
        model.onPreferencesChange = { preferences in
            settings.set(preferences.layout, for: keys.libraryLayout)
            settings.set(preferences.sort, for: keys.librarySort)
            settings.set(preferences.cardSize, for: keys.libraryCardSize)
        }
        library = model
        libraryWindow.show(AnyView(ClipboardLibraryView(module: self, model: model)), onClose: { [weak self] in
            self?.libraryClosed(model)
        })
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

    @discardableResult
    func copy(_ item: ClipboardItem, plainText: Bool = false) -> ClipboardPaster.Outcome? {
        put(item, paste: false, plainTextOnly: plainText)
    }

    @discardableResult
    func paste(_ item: ClipboardItem) -> ClipboardPaster.Outcome? {
        put(item, paste: true)
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
        var addedID: UUID?
        update { history in
            addedID = history.add(content, hash: ClipboardContent.hash(of: content), source: (nil, nil), at: now()).id
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
        update { history in
            history.deleteBoard(id: id)
            return []
        }
    }

    func pin(_ item: ClipboardItem, to boardID: UUID) {
        update { history in
            history.pin(itemID: item.id, to: boardID)
            return []
        }
    }

    /// `ids` in the order the library shows them, which the board then lists too (the newest pin goes first).
    func pin(ids: [UUID], to boardID: UUID) {
        update { history in
            for id in ids.reversed() { history.pin(itemID: id, to: boardID) }
            return []
        }
    }

    func unpin(_ item: ClipboardItem, from boardID: UUID) {
        update { history in
            history.unpin(itemID: item.id, from: boardID)
            return []
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
        case .image(let image): store?.imageURL(fileName: image.fileName).map { [$0] } ?? []
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
        var urls = fileURLs(of: item)
        if case .image = item.content {
            urls = urls.prefix(1).compactMap { try? ClipboardDragProvider.copyImage(at: $0, copiedAt: item.copiedAt) }
        }
        return ClipboardDragProvider.make(for: item.content, fileURLs: urls)
    }

    // MARK: Private

    /// Called by the library window closing, whether the user closed it or the module did.
    private func libraryClosed(_ model: ClipboardLibraryModel) {
        model.detach()
        if library === model { library = nil }
    }

    private func closeLibrary() {
        libraryWindow?.close()
        if let library { libraryClosed(library) }
    }

    /// Called by the monitor for each new copy.
    private func record(_ content: ClipboardContent, imageData: Data?, source: ClipboardMonitor.SourceApp) {
        guard let context, let keys, let store else { return }
        if let imageData, case .image(let image) = content {
            do {
                try store.saveImage(imageData, fileName: image.fileName)
            } catch {
                // An item whose image is missing could never be shown or pasted.
                let nsError = error as NSError
                context.logger.error("Saving a copied image failed (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public))")
                return
            }
        }
        update { history in
            history.add(content, hash: ClipboardContent.hash(of: content), source: source, at: now())
            return []
        }
        if context.settings.value(keys.showCopiedActivity) {
            context.activities.set(LiveActivity(
                id: "copied", expiresAfter: .milliseconds(1500),
                leading: AnyView(ClipboardActivityIcon(systemImage: "doc.on.clipboard.fill")),
                trailing: AnyView(ClipboardActivityIcon(systemImage: content.kind.systemImage))
            ))
        }
    }

    /// Puts the item on the pasteboard and moves it to the top. A paste always closes the notch, at once, so keyboard
    /// focus is back in the previous app before ⌘V is sent; a copy closes it when "close after action" is on.
    /// A failed write changes nothing and keeps the notch open. A paste from the library window hands the keyboard
    /// back to the app behind it and waits longer for that before sending ⌘V.
    @discardableResult
    private func put(_ item: ClipboardItem, paste: Bool, plainTextOnly: Bool = false) -> ClipboardPaster.Outcome? {
        guard let context, let keys, let paster else { return nil }
        let fromLibrary = paste && libraryWindow?.isFrontmost == true
        let outcome = paster.perform(
            item, imageURL: imageURL(of: item), paste: paste, plainTextOnly: plainTextOnly,
            delay: fromLibrary ? Self.libraryPasteDelay : nil
        )
        let closeAfterAction = context.settings.value(keys.closeAfterAction)
        switch outcome {
        case .pasted:
            context.presenter.close()
        case .copiedNeedsPermission:
            // Closed like a paste: the user pastes into the previous app, and activities show only beside the closed notch.
            context.presenter.close()
            context.activities.set(LiveActivity(
                id: "pasteHint", expiresAfter: .seconds(3),
                leading: AnyView(ClipboardActivityIcon(systemImage: "doc.on.clipboard.fill")),
                trailing: AnyView(ClipboardPasteKeyHint())
            ))
            // A newcomer no longer takes the notch from an activity of the same priority that is already live (the
            // "copied" one, or music), but the user has to see this one to know ⌘V is theirs to press.
            context.activities.raise(id: "pasteHint")
        case .copied:
            if closeAfterAction { context.presenter.close() }
        case .failed:
            // The notch stays open, where only a toast is visible.
            context.presenter.showToast(
                AnyView(ClipboardToast(text: "Không chép được mục này", systemImage: "exclamationmark.triangle.fill")),
                duration: .seconds(2)
            )
            return outcome
        }
        if fromLibrary { libraryWindow?.yieldKeyboardFocus() }
        update { history in
            history.touch(id: item.id, at: now())
            return []
        }
        return outcome
    }

    private func imageURL(of item: ClipboardItem) -> URL? {
        guard case .image(let image) = item.content else { return nil }
        return store?.imageURL(fileName: image.fileName)
    }

    private func hasImageFile(_ item: ClipboardItem, in store: ClipboardStore) -> Bool {
        guard case .image(let image) = item.content else { return true }
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
        if store.writeCount > 0 { store.deleteImages(for: removed) }
    }

    /// Applies a change, enforces the limits, deletes the images of removed items and schedules a save.
    /// `change` returns the items it removed. Does nothing while stopped.
    private func update(_ change: (inout ClipboardHistory) -> [ClipboardItem]) {
        guard let store else { return }
        var history = state.history
        let removed = change(&history) + prune(&history)
        guard history != state.history else { return }
        state.history = history
        store.deleteImages(for: removed)
        store.scheduleSave(history)
    }

    /// Removes items beyond the limits in Settings; returns them so their images can be deleted.
    private func prune(_ history: inout ClipboardHistory) -> [ClipboardItem] {
        guard let context, let keys else { return [] }
        let settings = context.settings
        return history.prune(
            limit: settings.value(keys.historyLimit),
            retention: settings.value(keys.retention),
            imageByteLimit: settings.value(keys.imageStorageLimitMB) * ClipboardStorageUsage.bytesPerMB,
            now: now()
        )
    }
}

/// Passes ⌘V on until closed; the paster keeps its sender, so this is how a stop drops a paste still waiting.
private final class KeystrokeGate: KeystrokeSending {
    var isOpen = true
    private let sender: any KeystrokeSending

    init(_ sender: any KeystrokeSending) {
        self.sender = sender
    }

    func sendPaste() {
        if isOpen { sender.sendPaste() }
    }
}
