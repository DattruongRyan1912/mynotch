import AppKit
import SwiftUI

/// The library's right-hand pane (⌘I): a small preview of the card in focus, what is known about it, and what can be done with it. A
/// closed board shows only that it is locked.
struct ClipboardInspectorView: View {
    static let width: CGFloat = 290

    let module: ClipboardModule
    @Bindable var model: ClipboardLibraryModel
    let requestName: (ClipboardLibraryBoardNaming) -> Void

    var body: some View {
        Group {
            switch model.inspector {
            case .nothing:
                placeholder("Chọn một mục để xem chi tiết", systemImage: "sidebar.right")
            case .locked:
                placeholder("Đang khoá", systemImage: "lock.fill")
            case .item(let info):
                if let item = model.focusedItem {
                    ClipboardInspectorItemView(module: module, model: model, item: item, info: info, requestName: requestName)
                        // A fresh view per item and per version of its words, so what was loaded for another cannot show here.
                        .id(ClipboardPreviewIdentity(id: item.id, contentHash: item.contentHash))
                }
            }
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chi tiết")
    }

    private func placeholder(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct ClipboardInspectorItemView: View {
    let module: ClipboardModule
    let model: ClipboardLibraryModel
    let item: ClipboardItem
    let info: ClipboardInspectorInfo
    let requestName: (ClipboardLibraryBoardNaming) -> Void

    @Environment(\.notchAccent) private var accent
    /// Worked out once for this item: the cut of a 2 MB text should not be made again at every change of the history.
    @State private var cache = ClipboardPreviewItemView.ContentCache()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                preview
                header
                details
                Divider()
                actions
            }
            .padding(14)
        }
    }

    // MARK: Preview

    private var preview: some View {
        ClipboardPreviewPane(
            content: cache.content(for: item), item: item, imageSource: module.previewImageSource(of: item), isCompact: true
        )
        .frame(height: 190)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: info.systemImage)
                .foregroundStyle(accent)
            Text(info.kindTitle)
                .font(.system(size: 14, weight: .semibold))
            if info.isEdited {
                Text("Đã sửa")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(accent.opacity(0.18)))
                    .foregroundStyle(accent)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Facts

    private var details: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 7) {
            row("Nguồn") {
                HStack(spacing: 6) {
                    if let bundleID = info.sourceBundleID, let icon = ClipboardIcons.app(bundleID: bundleID) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 16, height: 16)
                    }
                    Text(info.sourceAppName ?? "Không rõ")
                }
            }
            row("Đã chép") { Text(ClipboardInspectorFormat.date(info.copiedAt)) }
            row("Số lần chép") { Text(ClipboardInspectorFormat.times(info.timesCopied)) }
            row("Kích thước") { sizeText }
            if let language = info.language {
                switch language {
                case .code(let code): row("Mã") { Text(code == .generic ? ClipboardSearchTerms.codeTitle : code.title) }
                case .prose(let name): row("Ngôn ngữ") { Text(name) }
                }
            }
            row("Board") { Text(info.boards.isEmpty ? "Không có" : info.boards.joined(separator: ", ")) }
        }
        .font(.system(size: 12))
    }

    @ViewBuilder private var sizeText: some View {
        if let text = ClipboardInspectorFormat.size(info.size) {
            Text(text)
        } else {
            ClipboardInspectorLargeTextSize(item: item)
        }
    }

    private func row(_ title: String, @ViewBuilder _ value: () -> some View) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
                .frame(width: 78, alignment: .leading)
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { model.pasteFocused() } label: {
                    Label("Dán", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button { model.copySelection() } label: {
                    Label("Chép", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 8) {
                pinMenu
                Button { model.editFocused() } label: {
                    Label("Sửa…", systemImage: "pencil").frame(maxWidth: .infinity)
                }
                .disabled(!info.canEdit)
                .help(info.canEdit ? "Sửa nội dung" : "Chỉ sửa được văn bản, mã và link")
            }
            Button(role: .destructive) { model.requestDelete([item.id]) } label: {
                Label("Xoá", systemImage: "trash").frame(maxWidth: .infinity)
            }
        }
        .controlSize(.regular)
    }

    /// Each board toggles the pin, as the card's menu does; a closed board takes nothing until it is opened.
    private var pinMenu: some View {
        let pinned = Set(model.history.boards(containing: item.id).map(\.id))
        return Menu {
            ForEach(model.history.boards) { board in
                Toggle(board.name, isOn: Binding(
                    get: { pinned.contains(board.id) },
                    set: { $0 ? module.pin(item, to: board.id) : module.unpin(item, from: board.id) }
                ))
                .disabled(board.isLocked)
            }
            if !model.history.boards.isEmpty { Divider() }
            Button("Board mới…", systemImage: "plus") { requestName(.create(pinning: [item.id])) }
        } label: {
            Label("Ghim vào board…", systemImage: "pin").frame(maxWidth: .infinity)
        }
    }
}

/// The numbers of a text too long to count while drawing: counted off the main actor, shown when ready.
struct ClipboardInspectorLargeTextSize: View {
    let item: ClipboardItem
    @State private var stats: ClipboardTextStats?

    var body: some View {
        Group {
            if let stats, let text = ClipboardInspectorFormat.size(.text(stats)) {
                Text(text)
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Đang đếm…").foregroundStyle(.secondary)
                }
            }
        }
        .task(id: item.contentHash) {
            guard let text = item.content.plainText else { return }
            let counted = await ClipboardTextStats.load(text)
            if !Task.isCancelled { stats = counted }
        }
    }
}
