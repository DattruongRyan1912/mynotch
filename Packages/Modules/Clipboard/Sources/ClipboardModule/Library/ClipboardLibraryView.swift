import SwiftUI

/// The clipboard library window: a sidebar of boards, kinds and apps, and the cards beside it.
struct ClipboardLibraryView: View {
    let module: ClipboardModule
    @Bindable var model: ClipboardLibraryModel

    @State private var visibility = NavigationSplitViewVisibility.all
    @State private var naming: ClipboardLibraryBoardNaming?
    @State private var boardName = ""

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            ClipboardLibrarySidebar(module: module, model: model, requestName: startNaming)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 320)
        } detail: {
            ClipboardLibraryContentView(module: module, model: model, requestName: startNaming)
                .safeAreaInset(edge: .top, spacing: 0) { accessibilityHint }
                .navigationSubtitle("\(model.title) · \(model.items.count) mục")
        }
        // The toolbar of a window hosted like this showed no sidebar toggle when inspected off screen, so it gets its
        // own, and the split view's is removed in case it does appear, so there are never two.
        .toolbar(removing: .sidebarToggle)
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Tìm trong clipboard")
        .toolbar { toolbarContent }
        .frame(minWidth: 760, minHeight: 480)
        // While the window is open: when it appears, then every 2 s, so the hint goes by itself once it is allowed.
        .task {
            while !Task.isCancelled {
                module.refreshAccessibility()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        // The alerts' own dismissal is ignored: their buttons change the state they show, so the answer is never
        // lost to the order in which SwiftUI runs a button and dismisses the alert.
        .alert(namingTitle, isPresented: Binding(get: { naming != nil }, set: { _ in })) {
            TextField("Tên board", text: $boardName)
            Button(namingButton, action: commitNaming)
            Button("Huỷ", role: .cancel) { naming = nil }
        }
        .alert("Xoá cả mục đã ghim?", isPresented: Binding(get: { model.pendingDeletion != nil }, set: { _ in })) {
            Button("Xoá", role: .destructive) { model.confirmDelete() }
            Button("Huỷ", role: .cancel) { model.cancelDelete() }
        } message: {
            Text("\(model.pendingDeletion?.count ?? 0) mục sẽ bị xoá khỏi lịch sử và khỏi mọi board.")
        }
    }

    /// Under the toolbar while a click would paste without Accessibility.
    @ViewBuilder private var accessibilityHint: some View {
        if module.state.needsAccessibility {
            VStack(spacing: 0) {
                ClipboardAccessibilityHint(look: .library) { module.requestAccessibility() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                Divider()
            }
            .background(.bar)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation { visibility = visibility == .detailOnly ? .all : .detailOnly }
            } label: {
                Label("Thanh bên", systemImage: "sidebar.left")
            }
            .help("Ẩn hoặc hiện thanh bên")
        }
        ToolbarItemGroup {
            Menu {
                Picker("Sắp xếp", selection: $model.sort) {
                    ForEach(ClipboardLibrarySort.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label("Sắp xếp", systemImage: "arrow.up.arrow.down")
            }
            .help("Sắp xếp")

            Menu {
                Picker("Loại", selection: $model.kindFilter) {
                    Text("Tất cả loại").tag(ClipboardKind?.none)
                    ForEach(ClipboardKind.libraryOrder, id: \.self) { kind in
                        Label(kind.title, systemImage: kind.systemImage).tag(ClipboardKind?.some(kind))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label("Lọc theo loại", systemImage: model.kindFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
            .help("Lọc theo loại")
        }
        ToolbarItemGroup {
            if model.layout == .grid {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.3x3")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { model.cardSize.sliderValue },
                            set: { model.cardSize = ClipboardLibraryCardSize(sliderValue: $0) }
                        ),
                        in: 0...2, step: 1
                    )
                    .frame(width: 80)
                    .labelsHidden()
                    Image(systemName: "square.grid.2x2")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
                .help("Cỡ thẻ")
            }
            Picker("Kiểu xem", selection: $model.layout) {
                Label("Lưới", systemImage: "square.grid.2x2").tag(ClipboardLibraryLayout.grid)
                Label("Danh sách", systemImage: "list.bullet").tag(ClipboardLibraryLayout.list)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Lưới hoặc danh sách")
        }
        ToolbarItem {
            Button {
                startNaming(.create(pinning: []))
            } label: {
                Label("Board mới", systemImage: "folder.badge.plus")
            }
            .help("Board mới")
        }
    }

    // MARK: Naming a board

    private var namingTitle: String {
        if case .rename = naming { "Đổi tên board" } else { "Board mới" }
    }

    private var namingButton: String {
        if case .rename = naming { "Lưu" } else { "Tạo" }
    }

    private func startNaming(_ request: ClipboardLibraryBoardNaming) {
        if case .rename(let id) = request {
            boardName = model.history.boards.first { $0.id == id }?.name ?? ""
        } else {
            boardName = ""
        }
        naming = request
    }

    private func commitNaming() {
        guard let request = naming else { return }
        naming = nil
        switch request {
        case .create(let ids): model.createBoard(named: boardName, pinning: ids)
        case .rename(let id): module.renameBoard(id, to: boardName)
        }
    }
}
