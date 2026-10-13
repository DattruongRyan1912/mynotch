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
        optionalPermissions: [.accessibility],
        order: 100
    )

    let state = ClipboardState()
    /// Set while running; tests wait for its writes.
    private(set) var store: ClipboardStore?
    private let pasteboard: any PasteboardAccess
    private let keystrokes: any KeystrokeSending
    private let frontmostApp: () -> ClipboardMonitor.SourceApp
    private let isTrusted: () -> Bool
    private let pasteboardAccessBehavior: () -> NSPasteboard.AccessBehavior
    private let now: () -> Date
    private var context: ModuleContext?
    private var keys: ClipboardSettingKeys?
    private var monitor: ClipboardMonitor?
    private var paster: ClipboardPaster?

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
            pasteboardAccessBehavior: { NSPasteboard.general.accessBehavior }
        )
    }

    /// Tests pass fakes, so they never touch the system pasteboard or post key events.
    init(
        pasteboard: any PasteboardAccess,
        keystrokes: any KeystrokeSending,
        frontmostApp: @escaping () -> ClipboardMonitor.SourceApp,
        isTrusted: @escaping () -> Bool,
        pasteboardAccessBehavior: @escaping () -> NSPasteboard.AccessBehavior,
        now: @escaping () -> Date = { .now }
    ) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.frontmostApp = frontmostApp
        self.isTrusted = isTrusted
        self.pasteboardAccessBehavior = pasteboardAccessBehavior
        self.now = now
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
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
        history.removeDanglingPins()
        let removed = prune(&history)
        state.history = history
        store.deleteImages(for: removed)
        if history != loaded { store.scheduleSave(history) }
        refreshPasteboardAccess()

        paster = ClipboardPaster(pasteboard: pasteboard, keystrokes: keystrokes, scheduler: context.scheduler, isTrusted: isTrusted)
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
        context.run { [weak self] in
            // The first value arrives at once and prunes nothing new; later ones apply a changed limit right away.
            for await _ in Observations({ (settings.value(keys.historyLimit), settings.value(keys.retention), settings.value(keys.imageStorageLimitMB)) }) {
                self?.update { _ in [] }
            }
        }
    }

    /// Writes any unsaved change before returning, so quitting right after a copy keeps it.
    public func stop() async {
        monitor?.stop()
        monitor = nil
        paster = nil
        context = nil
        keys = nil
        let store = store
        self.store = nil
        await store?.flush()
        state.reset()
    }

    public func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id, title: "Clipboard", systemImage: "doc.on.clipboard",
            preferredHeight: 230, acceptsKeyboard: true, content: AnyView(ClipboardTabView(module: self))
        )
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        refreshPasteboardAccess()
        let directory = environment.storage.directory
        return AnyView(ClipboardSettingsView(
            settings: environment.settings,
            keys: ClipboardSettingKeys(environment.settings),
            usage: environment.isRunning ? .live(state) : .disk(directory),
            clear: { [weak self] range in await self?.clearHistory(range, directory: directory) },
            pasteboardAccessBehavior: pasteboardAccessBehavior
        ))
    }

    /// The ⌃⌥V shortcut.
    func openTab() {
        context?.presenter.open(tab: descriptor.id)
    }

    /// Re-read when the tab or Settings appear, since the user changes it in System Settings.
    func refreshPasteboardAccess() {
        let denied = pasteboardAccessBehavior() == .alwaysDeny
        if state.pasteboardDenied != denied { state.pasteboardDenied = denied }
    }

    // MARK: Actions used by the tab

    /// A click or Return on a card: the click action from Settings.
    func activate(_ item: ClipboardItem) {
        guard let context, let keys else { return }
        put(item, paste: context.settings.value(keys.clickAction) == .paste)
    }

    func copy(_ item: ClipboardItem, plainText: Bool = false) {
        put(item, paste: false, plainTextOnly: plainText)
    }

    func paste(_ item: ClipboardItem) {
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
        update { $0.remove(ids: [item.id]) }
    }

    func clearHistory(_ range: ClipboardClearRange) {
        update { $0.clear(newerThan: range.cutoff(from: now())) }
    }

    /// From Settings, which also works while the module is stopped: then the files are edited directly.
    func clearHistory(_ range: ClipboardClearRange, directory: URL) async {
        if store != nil {
            clearHistory(range)
            return
        }
        // A module that never ran has nothing to clear, and Settings must not create its folder.
        guard FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        let store = ClipboardStore(directory: directory, scheduler: TaskScheduler(), logger: Log.logger(category: descriptor.id.rawValue), now: now)
        var history = store.load()
        history.removeDanglingPins()
        store.deleteImages(for: history.clear(newerThan: range.cutoff(from: now())))
        store.scheduleSave(history)
        await store.flush()
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

    // MARK: Private

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
    private func put(_ item: ClipboardItem, paste: Bool, plainTextOnly: Bool = false) {
        guard let context, let keys, let paster else { return }
        let outcome = paster.perform(item, imageURL: imageURL(of: item), paste: paste, plainTextOnly: plainTextOnly)
        let closeAfterAction = context.settings.value(keys.closeAfterAction)
        switch outcome {
        case .pasted:
            context.presenter.close()
        case .copied:
            if closeAfterAction { context.presenter.close() }
        case .copiedNeedsPermission:
            showHint("Nhấn ⌘V để dán", id: "pasteHint")
            if closeAfterAction { context.presenter.close() }
        case .failed:
            // The notch stays open so the user sees the item was not copied.
            showHint("Không chép được mục này", id: "copyFailed")
            return
        }
        update { history in
            history.touch(id: item.id, at: now())
            return []
        }
    }

    private func imageURL(of item: ClipboardItem) -> URL? {
        guard case .image(let image) = item.content else { return nil }
        return store?.imageURL(fileName: image.fileName)
    }

    private func showHint(_ text: String, id: String) {
        context?.activities.set(LiveActivity(
            id: id, expiresAfter: .seconds(3),
            leading: AnyView(ClipboardActivityIcon(systemImage: "doc.on.clipboard.fill")),
            trailing: AnyView(ClipboardActivityText(text: text))
        ))
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
