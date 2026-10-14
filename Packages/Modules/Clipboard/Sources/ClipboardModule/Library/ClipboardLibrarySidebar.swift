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

    var body: some View {
        List(selection: selection) {
            Label("Tất cả", systemImage: "clock")
                .badge(model.counts.all)
                .tag(ClipboardLibrarySelection.all)
            Section {
                ForEach(model.history.boards) { board in
                    boardRow(board)
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

    private func boardRow(_ board: ClipboardBoard) -> some View {
        Label(board.name, systemImage: board.systemImage)
            .badge(model.counts.boards[board.id] ?? 0)
            .tag(ClipboardLibrarySelection.board(board.id))
            .listRowBackground(dropTarget == board.id ? Color.accentColor.opacity(0.3) : nil)
            .onDrop(of: [.item], isTargeted: ClipboardLibraryDrop.targeting(board.id, in: $dropTarget)) { _, _ in
                model.drop(onBoard: board.id)
            }
            .contextMenu {
                Button("Đổi tên…", systemImage: "pencil") { requestName(.rename(board.id)) }
                Button("Xoá board “\(board.name)”", systemImage: "trash", role: .destructive) { module.deleteBoard(board.id) }
            }
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
