import AppKit
import MyNotchCore
import NotchUI
import Observation
import SwiftUI
import UniformTypeIdentifiers

@Observable
final class ShelfState {
    /// Nil while the module is stopped.
    var store: ShelfStore?
    /// The card whose share picker is shown.
    var sharingID: UUID?
    /// The file cards picked for an action, in the order they were picked (the page order of a merged PDF).
    var selection: [UUID] = []
    /// The choice used last in each group of the "Hành động" row; a file dropped on the group runs it.
    var preferred: [ShelfActionGroup: FileAction] = [:]
    /// The action that is running, or the report of the last one.
    let actions = FileActionRunner()
}

/// A shelf in the notch: drop files, links or text on it, take them out again later.
public final class ShelfModule: FeatureModule {
    public let descriptor = ModuleDescriptor(
        id: "shelf",
        displayName: "Khay",
        systemImage: "tray.and.arrow.down",
        defaultEnabled: true,
        order: 800
    )

    static let dropTypes: [UTType] = [.fileURL, .url, .plainText, .image]

    let state = ShelfState()
    private(set) var context: ModuleContext?
    private(set) var keys: ShelfSettingKeys?

    private let notifications: NotificationCenter
    private var isObservingQuit = false
    let pasteboard: any PasteboardWriting
    let recognizer: any TextRecognizing
    let cutter: any ForegroundCutting
    /// Where results go that have no card and no folder of their own (see `ResultsFolder`).
    let resultsFolder: URL
    /// Makes the card of a result; a seam for tests of a bookmark that fails.
    var makeCard: @Sendable (URL) throws -> ShelfItem.Kind = { try ShelfItem.Kind.file(at: $0) }

    public init() {
        notifications = .default
        pasteboard = SystemPasteboard()
        recognizer = VisionTextRecognizer()
        cutter = VisionForegroundCutter()
        resultsFolder = ResultsFolder.standard
    }

    /// Tests pass fakes, so they never run Vision, write a pasteboard or make a folder in Downloads.
    init(
        notifications: NotificationCenter, pasteboard: any PasteboardWriting = SystemPasteboard(),
        recognizer: any TextRecognizing = VisionTextRecognizer(), cutter: any ForegroundCutting = VisionForegroundCutter(),
        resultsFolder: URL = ResultsFolder.standard
    ) {
        self.notifications = notifications
        self.pasteboard = pasteboard
        self.recognizer = recognizer
        self.cutter = cutter
        self.resultsFolder = resultsFolder
    }

    public func start(_ context: ModuleContext) async throws(ModuleError) {
        do {
            try context.storage.ensureDirectories()
        } catch {
            throw .failed(reason: "Không tạo được thư mục lưu khay")
        }
        let keys = ShelfSettingKeys(context.settings)
        self.context = context
        self.keys = keys
        state.store = ShelfStore(directory: context.storage.directory, limit: context.settings.value(keys.maxItems), logger: context.logger)
        clearOnQuit(settings: context.settings, keys: keys, directory: context.storage.directory)
    }

    public func stop() async {
        state.actions.reset()
        state.store = nil
        state.sharingID = nil
        state.selection = []
        context = nil
        keys = nil
    }

    /// `stop` also runs for Pause, for disabling the module and for a retry, so only the app quitting clears the shelf.
    /// The modules are stopped before AppKit announces the quit, so it is cleared from its files, and on the posting
    /// thread: a block queued on the main queue could still be waiting when the process exits.
    private func clearOnQuit(settings: ModuleSettings, keys: ShelfSettingKeys, directory: URL) {
        guard !isObservingQuit else { return }
        isObservingQuit = true
        _ = notifications.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                guard settings.value(keys.clearOnQuit) else { return }
                (self?.state.store ?? ShelfStore(directory: directory, limit: ShelfSettingKeys.maxItemsRange.upperBound)).removeAll()
            }
        }
    }

    public func makeTab() -> NotchTab? {
        NotchTab(
            id: descriptor.id, title: "Khay", systemImage: descriptor.systemImage, preferredHeight: 184,
            dropTypes: Self.dropTypes,
            onDrop: { [weak self] in self?.drop($0) ?? false },
            content: AnyView(ShelfTabView(state: state, module: self))
        )
    }

    public func makeSettingsView(_ environment: ModuleSettingsEnvironment) -> AnyView? {
        AnyView(ShelfSettingsView(settings: environment.settings, keys: ShelfSettingKeys(environment.settings)))
    }

    /// Accepts the drop at once and loads it in the background, since promised files can take a while to arrive.
    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard let context, state.store != nil, !providers.isEmpty else { return false }
        context.run { [self] in _ = await add(providers: providers) }
        return true
    }

    /// Returns how many items were added.
    func add(providers: [NSItemProvider]) async -> Int { await addItems(providers: providers).count }

    /// The items the providers became, in the order of the drop (an item that was already there is moved to the
    /// front and counts).
    func addItems(providers: [NSItemProvider]) async -> [ShelfItem] {
        guard let store = state.store, let keys, let context else { return [] }
        var added: [ShelfItem] = []
        // The newest item goes first on the shelf, so the last provider goes in first and the order of the drop is kept.
        for provider in providers.reversed() {
            let kind = await ShelfDropLoader.load(provider, promisedDirectory: store.promisedDirectory)
            // The module may have stopped, or stopped and started again, while the file was arriving.
            guard !Task.isCancelled, state.store === store else {
                if let kind { store.deleteStoredCopy(of: kind) }
                return added
            }
            guard let kind else {
                let types = provider.registeredTypeIdentifiers.joined(separator: ", ")
                context.logger.notice("A dropped item had nothing the shelf can keep (types: \(types, privacy: .public))")
                continue
            }
            store.add(kind, limit: context.settings.value(keys.maxItems))
            if let item = store.items.first { added.insert(item, at: 0) }
        }
        return added
    }

    /// What a card carries when dragged out of the notch; nil when its file is gone. A file is looked up again, since
    /// it may have moved since the shelf was loaded.
    func dragWriter(for item: ShelfItem) -> (any NSPasteboardWriting)? {
        switch item.kind {
        case .text(let text): text as NSString
        case .link(let url): url as NSURL
        case .file: state.store?.refreshedURL(of: item).map { $0 as NSURL }
        }
    }

    /// Called when the drag of a card has ended, with the card as it was when the drag began: one that was dropped
    /// back on the shelf meanwhile was moved to the front, no longer matches and stays. A cancelled or refused drag
    /// removes nothing, and a promised copy is left for the next load to sweep, so the destination can finish reading it.
    func didDragEnd(_ item: ShelfItem, operation: NSDragOperation) {
        guard let context, let keys,
              ShelfDragOutcome.removesCard(operation: operation, removeAfterDragOut: context.settings.value(keys.removeAfterDragOut)),
              let store = state.store, store.items.contains(item) else { return }
        store.remove(id: item.id, deletingCopy: false)
    }

    /// Not while an action runs: it may still be reading a promised copy that removing its card would delete.
    func remove(_ item: ShelfItem) {
        guard !state.actions.isRunning else { return }
        state.selection.removeAll { $0 == item.id }
        state.store?.remove(id: item.id)
    }

    func removeAll() {
        guard !state.actions.isRunning else { return }
        state.selection = []
        state.store?.removeAll()
    }

    /// What the system's sharing services take for this item. Called when sharing, not when drawing.
    func shareItems(for item: ShelfItem) -> [Any] {
        switch item.kind {
        case .text(let text): [text]
        case .link(let url): [url]
        case .file: state.store?.refreshedURL(of: item).map { [$0] } ?? []
        }
    }

    func open(_ item: ShelfItem) {
        switch item.kind {
        case .link(let url): NSWorkspace.shared.open(url)
        case .file: state.store?.refreshedURL(of: item).map { _ = NSWorkspace.shared.open($0) }
        case .text: break
        }
    }

    func revealInFinder(_ item: ShelfItem) {
        guard let url = state.store?.refreshedURL(of: item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// The app is an agent, so it is activated first or the AirDrop sheet would stay behind other windows.
    func airDrop(_ item: ShelfItem) {
        let items = shareItems(for: item)
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: items) else { return }
        NSApp.activate()
        service.perform(withItems: items)
    }
}
