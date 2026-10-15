import CoreGraphics
import Foundation
import Observation

/// The notch tab's large preview (Space, ⌘Y) apart from the drawing: which card it shows, what the keys do while it is open, and the
/// pin that keeps the notch open under it. It follows the tab's own `ClipboardState` (the cards it shows and the selected one), the
/// same way the panel's and the library's models follow theirs, so the preview always shows the selected card, live.
@Observable
final class ClipboardTabPreviewModel: ClipboardPreviewHosting {
    /// The large preview of the selected card, which follows the selection while it is open.
    let preview = ClipboardPreviewState()

    /// Told when the preview opens or closes, so the window can be shown or taken away; set by the module.
    @ObservationIgnored var onPreviewChange: ((Bool) -> Void)?
    /// Keeps the notch open for as long as the preview is, the way a menu does: pinned before the window appears and unpinned after it
    /// is gone. Set by the tab, which has the notch's handle.
    @ObservationIgnored var pinNotch: ((Bool) -> Void)?
    /// Return: uses the card (the module's click action, the notch's verified paste path). The preview has closed by then.
    @ObservationIgnored var onActivate: ((ClipboardItem) -> Void)?
    /// The notch's window, as a frame (which tells the preview which display to appear on) and an identity (whose clicks are swallowed),
    /// while the tab is on screen; set by the tab's key hook.
    @ObservationIgnored var hostWindow: () -> (frame: CGRect?, id: ObjectIdentifier?) = { (nil, nil) }

    @ObservationIgnored private let state: ClipboardState
    /// The card shown, to tell it going away (deleted, its board locked) from the selection moving on.
    @ObservationIgnored private var anchorID: UUID?

    init(state: ClipboardState) {
        self.state = state
        // Pinned before the window shows, and unpinned once it is gone.
        preview.onChange = { [weak self] open in
            guard let self else { return }
            if open {
                pinNotch?(true)
                onPreviewChange?(true)
            } else {
                onPreviewChange?(false)
                pinNotch?(false)
            }
        }
        state.observeShown(self) { [weak self] in self?.reconcile() }
    }

    isolated deinit {
        state.stopObservingShown(self)
    }

    var isPreviewOpen: Bool { preview.isOpen }

    /// The selected card while the preview is open.
    var previewedItem: ClipboardItem? {
        preview.isOpen ? previewableSelection : nil
    }

    /// Space and ⌘Y: opens the preview on the selected card, or closes it.
    func togglePreview() {
        if preview.isOpen {
            preview.close()
        } else if let item = previewableSelection {
            // The first card only stands in for a selection nobody made; a copy that arrives while the preview is open must not move
            // the preview (or Return) to it.
            state.selectedID = item.id
            anchorID = item.id
            preview.open()
        }
    }

    func closePreview() {
        preview.close()
    }

    /// A key the tab's search field is about to get. True when the preview took it, so the field never sees it. The field is the
    /// only place to type in the notch, so `target` is always `.searchField` here.
    func handlePreviewKey(_ key: ClipboardPreviewKeys.Key, target: ClipboardPreviewKeys.Target, hasMarkedText: Bool) -> Bool {
        let command = preview.command(
            for: key, target: target, hasMarkedText: hasMarkedText, searchIsEmpty: state.query.text.isEmpty,
            suggestionsAreOpen: state.suggestions.isOpen, hasItem: previewableSelection != nil
        )
        switch command {
        case nil: return false
        case .ignore: return true
        case .toggle: togglePreview()
        case .close: preview.close()
        case .activate: activateShown()
        }
        return true
    }

    // MARK: Private

    private var selectedItem: ClipboardItem? {
        let items = state.visibleItems
        guard let id = ClipboardSelection.current(in: items.map(\.id), selected: state.selectedID) else { return nil }
        return items.first { $0.id == id }
    }

    /// The selected card, unless it may not be shown: the notch's stack is on (no cards), or it is pinned to a locked board.
    private var previewableSelection: ClipboardItem? {
        guard !state.stack.isOn, let item = selectedItem, state.history.canPreview(item.id) else { return nil }
        return item
    }

    /// Before anything is written or pasted, so the preview is never in the way of the keyboard or of ⌘V.
    private func activateShown() {
        guard let item = previewableSelection else { return }
        preview.close()
        state.selectedID = item.id
        onActivate?(item)
    }

    /// The cards or the selection changed: a card that is gone (deleted, or its board locked) takes its preview with it, rather than the
    /// preview moving on to whatever the selection falls back to; one that was only moved from, or searched away, is followed.
    private func reconcile() {
        guard preview.isOpen else { return }
        if let anchorID, !state.history.items.contains(where: { $0.id == anchorID }) {
            preview.close()
            return
        }
        guard let item = previewableSelection else {
            preview.close()
            return
        }
        anchorID = item.id
    }
}
