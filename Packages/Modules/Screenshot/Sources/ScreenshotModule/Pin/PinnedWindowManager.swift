import AppKit
import CoreGraphics
import Foundation

/// Callbacks executed by context menu actions on a pinned window.
struct PinnedWindowActions: Sendable {
    var copy: @MainActor () -> Void
    var ocr: @MainActor () -> Void
    var liftSubject: (@MainActor () -> Void)?
    var edit: (@MainActor () -> Void)?
    var saveAs: (@MainActor () -> Void)?

    init(
        copy: @escaping @MainActor () -> Void,
        ocr: @escaping @MainActor () -> Void,
        liftSubject: (@MainActor () -> Void)? = nil,
        edit: (@MainActor () -> Void)? = nil,
        saveAs: (@MainActor () -> Void)? = nil
    ) {
        self.copy = copy
        self.ocr = ocr
        self.liftSubject = liftSubject
        self.edit = edit
        self.saveAs = saveAs
    }
}

/// Interface for managing active floating screenshot panels.
@MainActor
protocol PinnedWindowManaging: AnyObject {
    var pinnedItems: [PinnedItem] { get }
    @discardableResult
    func pin(
        image: CGImage,
        scale: CGFloat,
        record: CaptureRecord?,
        sourceFrame: CGRect?,
        actions: PinnedWindowActions
    ) -> PinnedItem
    func close(id: UUID)
    func close(recordID: UUID)
    func closeAll()
}

/// Production implementation of PinnedWindowManaging tracking live floating NSPanels.
@MainActor
final class PinnedWindowManager: PinnedWindowManaging {
    private var entries: [UUID: (item: PinnedItem, panel: PinnedWindowPanel, view: PinnedWindowView)] = [:]
    private(set) var pinnedItems: [PinnedItem] = []
    private let screens: () -> [NSScreen]

    init(screens: @escaping () -> [NSScreen] = { NSScreen.screens }) {
        self.screens = screens
    }

    @discardableResult
    func pin(
        image: CGImage,
        scale: CGFloat,
        record: CaptureRecord?,
        sourceFrame: CGRect?,
        actions: PinnedWindowActions
    ) -> PinnedItem {
        let item = PinnedItem(
            recordID: record?.id,
            image: image,
            scale: scale,
            sourceFrame: sourceFrame
        )

        let allScreens = screens()
        let targetScreen: NSScreen?
        if let source = sourceFrame {
            targetScreen = allScreens.first(where: { $0.frame.intersects(source) }) ?? allScreens.first
        } else {
            targetScreen = allScreens.first
        }
        let visibleFrame = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let initialFrame = PinnedWindowState.initialFrame(
            baseSize: item.pointSize,
            sourceFrame: sourceFrame,
            visibleScreenFrame: visibleFrame
        )

        let state = PinnedWindowState(baseSize: item.pointSize)
        let panel = PinnedWindowPanel(contentRect: initialFrame)
        let view = PinnedWindowView(item: item, state: state, actions: actions) { [weak self, id = item.id] in
            self?.close(id: id)
        }

        panel.contentView = view
        panel.orderFrontRegardless()

        entries[item.id] = (item: item, panel: panel, view: view)
        pinnedItems.append(item)
        return item
    }

    func close(id: UUID) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        entry.panel.orderOut(nil)
        entry.panel.contentView = nil
        entry.panel.close()
        pinnedItems.removeAll(where: { $0.id == id })
    }

    func close(recordID: UUID) {
        let matchingIDs = entries.values.compactMap { entry in
            entry.item.recordID == recordID ? entry.item.id : nil
        }
        for id in matchingIDs {
            close(id: id)
        }
    }

    func closeAll() {
        let allIDs = Array(entries.keys)
        for id in allIDs {
            close(id: id)
        }
    }
}
