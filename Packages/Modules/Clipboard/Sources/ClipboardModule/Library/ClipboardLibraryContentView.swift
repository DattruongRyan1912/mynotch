import AppKit
import SwiftUI

/// The library's content: the boards row (for the whole history), then the cards as a lazy grid or list. Click selects,
/// double click or Return does the click action from Settings, drag moves a card out or onto a board.
struct ClipboardLibraryContentView: View {
    private static let padding: CGFloat = 20
    private static let spacing: CGFloat = 12

    let module: ClipboardModule
    @Bindable var model: ClipboardLibraryModel
    let requestName: (ClipboardLibraryBoardNaming) -> Void

    @State private var width: CGFloat = 0
    /// Bumped to give the cards the keyboard back, e.g. after clicking one while the search field had it.
    @State private var keyboardRequest = 0
    @State private var dropTarget: UUID?
    @State private var dragWatch: Task<Void, Never>?
    /// The board whose icon and colour are being chosen, in a popover from its tile.
    @State private var styling: UUID?

    private var columnCount: Int {
        model.cardSize.columnCount(forWidth: Double(width - 2 * Self.padding), spacing: Self.spacing)
    }

    var body: some View {
        ScrollViewReader { proxy in
            // Redraws the relative times each minute.
            TimelineView(.everyMinute) { _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if model.showsBoardTiles { boards }
                        history
                    }
                    .padding(Self.padding)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            // A new focus scrolls only as far as needed, so a click on a visible card does not move the list.
            .onChange(of: model.focusID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) }
            }
        }
        .onChange(of: columnCount, initial: true) { _, count in model.columns = count }
        .background {
            ClipboardLibraryKeyboard(
                focusRequest: keyboardRequest, onCommand: perform, onCopy: { model.copySelection() }, onSelectAll: { model.selectAll() }
            )
        }
        .overlay(alignment: .bottom) { noticeView }
    }

    // MARK: Boards

    private var boards: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Boards")
                .font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: Self.spacing) {
                    ForEach(Array(model.history.boards.enumerated()), id: \.element.id) { index, board in
                        Button {
                            model.selection = .board(board.id)
                        } label: {
                            ClipboardLibraryBoardTile(
                                board: board, count: model.counts.boards[board.id] ?? 0, isTargeted: dropTarget == board.id
                            )
                        }
                        .buttonStyle(.plain)
                        .onDrop(of: [.item], isTargeted: ClipboardLibraryDrop.targeting(board.id, in: $dropTarget)) { _, _ in
                            model.drop(onBoard: board.id)
                        }
                        .popover(isPresented: Binding(get: { styling == board.id }, set: { if !$0, styling == board.id { styling = nil } })) {
                            ClipboardBoardStylePicker(
                                board: board, onIcon: { module.setBoardIcon(board.id, to: $0) }, onColor: { module.setBoardColor(board.id, to: $0) }
                            )
                        }
                        .contextMenu {
                            Button("Đổi tên…", systemImage: "pencil") { requestName(.rename(board.id)) }
                            Button("Đổi biểu tượng và màu…", systemImage: "paintpalette") { styling = board.id }
                            Button("Chuyển sang trái", systemImage: "arrow.left") { module.moveBoard(board.id, by: -1) }
                                .disabled(index == 0)
                            Button("Chuyển sang phải", systemImage: "arrow.right") { module.moveBoard(board.id, by: 1) }
                                .disabled(index == model.history.boards.count - 1)
                            Divider()
                            Button("Xoá board “\(board.name)”", systemImage: "trash", role: .destructive) { module.deleteBoard(board.id) }
                        }
                        .accessibilityAction(named: "Chuyển sang trái") { if index > 0 { module.moveBoard(board.id, by: -1) } }
                        .accessibilityAction(named: "Chuyển sang phải") {
                            if index < model.history.boards.count - 1 { module.moveBoard(board.id, by: 1) }
                        }
                        .accessibilityAction(named: "Đổi biểu tượng và màu") { styling = board.id }
                    }
                    Button {
                        requestName(.create(pinning: []))
                    } label: {
                        ClipboardLibraryNewBoardTile()
                    }
                    .buttonStyle(.plain)
                }
                .padding(2)
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: History

    @ViewBuilder private var history: some View {
        if let message = model.emptyMessage {
            empty(message)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if model.selection == .all {
                    Text("Lịch sử")
                        .font(.headline)
                }
                switch model.layout {
                case .grid: grid
                case .list: list
                }
            }
        }
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Self.spacing, alignment: .top), count: columnCount)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: Self.spacing) {
            ForEach(model.items) { item in
                interactive(item) {
                    ClipboardLibraryCard(
                        item: item, size: model.cardSize, isSelected: model.selectedIDs.contains(item.id),
                        isPinned: model.pinnedIDs.contains(item.id), timeLabel: model.timeLabel(for: item),
                        accessibilityLabel: model.accessibilityLabel(for: item), imageURL: imageURL(of: item),
                        thumbnails: model.thumbnails
                    )
                }
            }
        }
    }

    private var list: some View {
        LazyVStack(spacing: 4) {
            ForEach(model.items) { item in
                interactive(item) {
                    ClipboardLibraryRow(
                        item: item, isSelected: model.selectedIDs.contains(item.id), isPinned: model.pinnedIDs.contains(item.id),
                        timeLabel: model.timeLabel(for: item), accessibilityLabel: model.accessibilityLabel(for: item),
                        imageURL: imageURL(of: item), thumbnails: model.thumbnails
                    )
                }
            }
        }
    }

    private func empty(_ message: String) -> some View {
        ContentUnavailableView {
            Label(message, systemImage: model.selection.isBoard ? "tray" : "doc.on.clipboard")
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    // MARK: A card's behaviour

    private func interactive<Content: View>(_ item: ClipboardItem, @ViewBuilder content: () -> Content) -> some View {
        content()
            .id(item.id)
            .onTapGesture { click(item) }
            // Beside the single click, which stays immediate: the first click of a double click selects as usual.
            .simultaneousGesture(TapGesture(count: 2).onEnded { model.activate(item.id) })
            .onDrag { startDrag(item) }
            .contextMenu { menu(for: item) }
            .accessibilityAddTraits(model.selectedIDs.contains(item.id) ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { model.activate(item.id) }
    }

    @ViewBuilder private func menu(for item: ClipboardItem) -> some View {
        let count = model.selectedIDs.count
        if count > 1, model.selectedIDs.contains(item.id) {
            Menu("Ghim \(count) mục vào board", systemImage: "pin") {
                ForEach(model.history.boards) { board in
                    Button(board.name) { model.addSelection(toBoard: board.id) }
                }
                if !model.history.boards.isEmpty { Divider() }
                Button("Board mới…", systemImage: "plus") {
                    requestName(.create(pinning: model.items.map(\.id).filter(model.selectedIDs.contains)))
                }
            }
            Divider()
            Button("Xoá \(count) mục", systemImage: "trash", role: .destructive) { model.requestDelete() }
        } else {
            ClipboardCardMenu(
                module: module, item: item, shownBoardID: model.selection.boardID, onResult: { model.show($0) },
                onDelete: { model.requestDelete([$0.id]) }, onNewBoard: { requestName(.create(pinning: [item.id])) }
            )
        }
    }

    private func click(_ item: ClipboardItem) {
        let flags = NSEvent.modifierFlags
        model.select(item.id, mode: flags.contains(.command) ? .toggle : flags.contains(.shift) ? .range : .replace)
        keyboardRequest += 1
    }

    /// SwiftUI reports no end of a drag, so the library hears it ended once the mouse button is up again, a little
    /// later so a drop on a board has been handled first.
    private func startDrag(_ item: ClipboardItem) -> NSItemProvider {
        _ = model.beginDrag(of: item.id)
        dragWatch?.cancel()
        dragWatch = Task {
            repeat {
                try? await Task.sleep(for: .milliseconds(100))
            } while NSEvent.pressedMouseButtons & 1 != 0 && !Task.isCancelled
            try? await Task.sleep(for: .milliseconds(300))
            if !Task.isCancelled { model.endDrag() }
        }
        return module.dragProvider(for: item)
    }

    private func perform(_ command: ClipboardLibraryKeyCommand) {
        switch command {
        case .move(let direction, let extend): model.move(direction, extend: extend)
        case .activate: model.activateSelection()
        case .delete: model.requestDelete()
        case .clearSelection: model.clearSelection()
        }
    }

    private func imageURL(of item: ClipboardItem) -> URL? {
        guard case .image = item.content else { return nil }
        return module.fileURLs(of: item).first
    }

    // MARK: Notice

    @ViewBuilder private var noticeView: some View {
        if let notice = model.notice {
            Label(notice.text, systemImage: notice.systemImage)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(Color.primary.opacity(0.1)) }
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                // A newer notice has a new id, which restarts the wait.
                .task(id: notice.id) {
                    try? await Task.sleep(for: .seconds(1.8))
                    if !Task.isCancelled { model.dismissNotice(notice.id) }
                }
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

extension ClipboardLibrarySelection {
    var isBoard: Bool {
        if case .board = self { true } else { false }
    }

    var boardID: UUID? {
        if case .board(let id) = self { id } else { nil }
    }
}
