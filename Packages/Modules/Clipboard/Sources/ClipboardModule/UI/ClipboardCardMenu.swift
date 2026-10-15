import SwiftUI

/// A card's context menu (spec 3.4). A view of its own because SwiftUI evaluates it only when the menu opens, so
/// which transforms apply is worked out then rather than on every redraw of the card.
struct ClipboardCardMenu: View {
    /// Above this many UTF-8 bytes every transform is offered unchecked and a failure is reported after choosing it,
    /// so the menu still opens at once for a huge copy.
    static let transformCheckLimit = 200_000

    /// "Dán dạng văn bản thường" is for a rich text, whose plain paste differs from the default one, and for code, which a
    /// plain "Dán" already pastes as plain text but which the user may still look for here.
    static func offersPlainTextPaste(for item: ClipboardItem) -> Bool {
        if case .richText = item.content { return true }
        return item.isCode
    }

    let module: ClipboardModule
    let item: ClipboardItem
    /// The board on show, which "Bỏ ghim" unpins from; nil unpins from every board.
    var shownBoardID: UUID?
    /// Told what a copy or paste did, for a window that shows it.
    var onResult: (ClipboardPaster.Outcome?) -> Void = { _ in }
    /// Replaces deleting at once, for a window that asks before deleting a pinned item.
    var onDelete: ((ClipboardItem) -> Void)?
    /// Shows the inline name field; the new board gets this item pinned.
    let onNewBoard: () -> Void

    var body: some View {
        Button("Chép", systemImage: "doc.on.doc") { onResult(module.copy(item)) }
        Button("Dán", systemImage: "doc.on.clipboard") { onResult(module.paste(item)) }
        if case .richText = item.content {
            Button("Chép dạng văn bản thuần", systemImage: "textformat") { onResult(module.copy(item, plainText: true)) }
        }
        if Self.offersPlainTextPaste(for: item) {
            Button("Dán dạng văn bản thường", systemImage: "text.alignleft") { onResult(module.paste(item, plainText: true)) }
        }
        if item.content.kind == .text, let text = item.content.plainText {
            transforms(of: text)
        }
        boards
        if ClipboardModule.openableLink(of: item) != nil {
            Button("Mở link", systemImage: "safari") { module.openLink(item) }
        }
        if !module.fileURLs(of: item).isEmpty {
            Button("Hiện trong Finder", systemImage: "folder") { module.revealInFinder(item) }
        }
        Divider()
        Button("Xoá", systemImage: "trash", role: .destructive) {
            if let onDelete { onDelete(item) } else { module.delete(item) }
        }
    }

    private func transforms(of text: String) -> some View {
        let checks = text.utf8.count <= Self.transformCheckLimit
        return Menu("Biến đổi", systemImage: "wand.and.stars") {
            ForEach(TextTransform.allCases, id: \.self) { transform in
                Button(transform.title) {
                    if !module.apply(transform, to: item) {
                        module.showToast("Không áp dụng được", systemImage: "wand.and.stars")
                    }
                }
                .disabled(checks && transform.apply(text) == nil)
            }
        }
    }

    /// Each board toggles the pin; "Bỏ ghim" unpins from the board being shown, or from every board otherwise.
    @ViewBuilder private var boards: some View {
        let state = module.state
        let pinnedIn = state.history.boards(containing: item.id).map(\.id)
        Menu("Ghim vào board", systemImage: "pin") {
            ForEach(state.history.boards) { board in
                Toggle(board.name, isOn: Binding(
                    get: { pinnedIn.contains(board.id) },
                    set: { $0 ? module.pin(item, to: board.id) : module.unpin(item, from: board.id) }
                ))
            }
            if !state.history.boards.isEmpty { Divider() }
            Button("Board mới…", systemImage: "plus", action: onNewBoard)
        }
        if !pinnedIn.isEmpty {
            Button("Bỏ ghim", systemImage: "pin.slash") {
                let shown = shownBoardID.flatMap { pinnedIn.contains($0) ? [$0] : nil }
                for boardID in shown ?? pinnedIn { module.unpin(item, from: boardID) }
            }
        }
    }
}
