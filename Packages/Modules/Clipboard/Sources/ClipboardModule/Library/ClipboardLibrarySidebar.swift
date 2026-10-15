import AppKit
import SwiftUI

/// The board whose name the library's alert is asking for.
enum ClipboardLibraryBoardNaming: Equatable {
    /// A new board; `pinning` are the items to put in it once it exists.
    case create(pinning: [UUID])
    case rename(UUID)
}

/// The library's sidebar: the whole history, boards (drop cards on one to pin them), kinds and source apps, each with
/// how many items it holds.
struct ClipboardLibrarySidebar: View {
    let module: ClipboardModule
    @Bindable var model: ClipboardLibraryModel
    let requestName: (ClipboardLibraryBoardNaming) -> Void

    @State private var dropTarget: UUID?
    /// The board whose icon and colour are being chosen, in a popover from its row.
    @State private var styling: UUID?
    @Environment(\.notchAccent) private var accent

    var body: some View {
        List(selection: selection) {
            Label("Tất cả", systemImage: "clock")
                .badge(model.counts.all)
                .tag(ClipboardLibrarySelection.all)
            Section {
                ForEach(Array(model.history.boards.enumerated()), id: \.element.id) { index, board in
                    boardRow(board, at: index)
                }
                .onMove { source, destination in
                    guard let from = source.first, model.history.boards.indices.contains(from) else { return }
                    module.moveBoard(
                        model.history.boards[from].id, to: ClipboardBoardReorder.index(moving: from, toOffset: destination)
                    )
                }
            } header: {
                HStack {
                    Text("Boards")
                    Spacer()
                    Button {
                        requestName(.create(pinning: []))
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Board mới")
                }
            }
            Section("Loại") {
                ForEach(ClipboardKind.libraryOrder, id: \.self) { kind in
                    Label(kind.title, systemImage: kind.systemImage)
                        .badge(model.counts.kinds[kind] ?? 0)
                        .tag(ClipboardLibrarySelection.kind(kind))
                }
            }
            if !model.counts.apps.isEmpty {
                Section("Ứng dụng") {
                    ForEach(model.counts.apps) { app in
                        Label {
                            Text(app.name)
                        } icon: {
                            appIcon(app)
                        }
                        .badge(app.count)
                        .tag(ClipboardLibrarySelection.app(app.id))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// The list wants an optional selection; the model always has one.
    private var selection: Binding<ClipboardLibrarySelection?> {
        Binding(get: { model.selection }, set: { if let value = $0 { model.selection = value } })
    }

    private func boardRow(_ board: ClipboardBoard, at index: Int) -> some View {
        let count = model.history.boards.count
        return Label {
            Text(board.name)
        } icon: {
            // The default colour is the sidebar's own, which also turns white on a selected row.
            if board.color == .accent {
                Image(systemName: board.systemImage)
            } else {
                Image(systemName: board.systemImage).foregroundStyle(board.color.color(accent: accent))
            }
        }
        .badge(model.counts.boards[board.id] ?? 0)
        .tag(ClipboardLibrarySelection.board(board.id))
        .listRowBackground(dropTarget == board.id ? accent.opacity(0.3) : nil)
        .onDrop(of: [.item], delegate: ClipboardCardDropDelegate(boardID: board.id, model: model, target: $dropTarget))
        .popover(isPresented: Binding(get: { styling == board.id }, set: { if !$0, styling == board.id { styling = nil } }), arrowEdge: .trailing) {
            ClipboardBoardStylePicker(
                board: board, onIcon: { module.setBoardIcon(board.id, to: $0) }, onColor: { module.setBoardColor(board.id, to: $0) }
            )
        }
        .contextMenu {
            Button("Đổi tên…", systemImage: "pencil") { requestName(.rename(board.id)) }
            Button("Đổi biểu tượng và màu…", systemImage: "paintpalette") { styling = board.id }
            Button("Chuyển lên", systemImage: "arrow.up") { module.moveBoard(board.id, by: -1) }
                .disabled(index == 0)
            Button("Chuyển xuống", systemImage: "arrow.down") { module.moveBoard(board.id, by: 1) }
                .disabled(index == count - 1)
            Divider()
            Button("Xoá board “\(board.name)”", systemImage: "trash", role: .destructive) { module.deleteBoard(board.id) }
        }
        .accessibilityAction(named: "Chuyển lên") { if index > 0 { module.moveBoard(board.id, by: -1) } }
        .accessibilityAction(named: "Chuyển xuống") { if index < count - 1 { module.moveBoard(board.id, by: 1) } }
        .accessibilityAction(named: "Đổi biểu tượng và màu") { styling = board.id }
    }

    @ViewBuilder
    private func appIcon(_ app: ClipboardLibraryApp) -> some View {
        if let bundleID = app.bundleID, let icon = ClipboardIcons.app(bundleID: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: "app")
        }
    }
}

/// Takes the cards being dragged from the library onto a board of the sidebar. Says no to anything else, a board dragged by
/// the list among them included, so a reorder is left to the list and does not light the row up as a target.
struct ClipboardCardDropDelegate: DropDelegate {
    let boardID: UUID
    let model: ClipboardLibraryModel
    @Binding var target: UUID?

    func validateDrop(info: DropInfo) -> Bool {
        !model.draggingIDs.isEmpty
    }

    func dropEntered(info: DropInfo) {
        target = boardID
    }

    func dropExited(info: DropInfo) {
        if target == boardID { target = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        if target == boardID { target = nil }
        return model.drop(onBoard: boardID)
    }
}

enum ClipboardLibraryDrop {
    /// The `isTargeted` binding of one drop target among several that share a `@State` id.
    static func targeting(_ id: UUID, in target: Binding<UUID?>) -> Binding<Bool> {
        Binding(
            get: { target.wrappedValue == id },
            set: { isTargeted in
                if isTargeted {
                    target.wrappedValue = id
                } else if target.wrappedValue == id {
                    target.wrappedValue = nil
                }
            }
        )
    }
}
