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
    private var context: ModuleContext?
    private var keys: ShelfSettingKeys?

    private let notifications: NotificationCenter
    private var isObservingQuit = false

    public init() { notifications = .default }

    init(notifications: NotificationCenter) { self.notifications = notifications }

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
        state.store = nil
        state.sharingID = nil
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
            id: descriptor.id, title: "Khay", systemImage: descriptor.systemImage, preferredHeight: 170,
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
    func add(providers: [NSItemProvider]) async -> Int {
        guard let store = state.store, let keys, let context else { return 0 }
        var added = 0
        // The newest item goes first on the shelf, so the last provider goes in first and the order of the drop is kept.
        for provider in providers.reversed() {
            let kind = await ShelfDropLoader.load(provider, promisedDirectory: store.promisedDirectory)
            // The module may have stopped, or stopped and started again, while the file was arriving.
            guard !Task.isCancelled, state.store === store else {
                if let kind { store.deleteStoredCopy(of: kind) }
                return added
            }
            guard let kind else { continue }
            store.add(kind, limit: context.settings.value(keys.maxItems))
            added += 1
        }
        return added
    }

    /// What a card carries when dragged out of the notch.
    func dragProvider(for item: ShelfItem) -> NSItemProvider {
        switch item.kind {
        case .text(let text): NSItemProvider(object: text as NSString)
        case .link(let url): NSItemProvider(object: url as NSURL)
        case .file: state.store?.url(of: item).map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider()
        }
    }

    /// Called once the drag of a card has ended, with the card as it was when the drag began: one that was dropped
    /// back on the shelf meanwhile was moved to the front, no longer matches and stays.
    func didDragOut(_ item: ShelfItem) {
        guard let context, let keys, context.settings.value(keys.removeAfterDragOut),
              let store = state.store, store.items.contains(item) else { return }
        store.remove(id: item.id, deletingCopy: false)
    }

    func remove(_ item: ShelfItem) { state.store?.remove(id: item.id) }
    func removeAll() { state.store?.removeAll() }

    /// What the system's sharing services take for this item.
    func shareItems(for item: ShelfItem) -> [Any] {
        switch item.kind {
        case .text(let text): [text]
        case .link(let url): [url]
        case .file: state.store?.url(of: item).map { [$0] } ?? []
        }
    }

    func open(_ item: ShelfItem) {
        switch item.kind {
        case .link(let url): NSWorkspace.shared.open(url)
        case .file: state.store?.url(of: item).map { _ = NSWorkspace.shared.open($0) }
        case .text: break
        }
    }

    func revealInFinder(_ item: ShelfItem) {
        guard let url = state.store?.url(of: item) else { return }
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
