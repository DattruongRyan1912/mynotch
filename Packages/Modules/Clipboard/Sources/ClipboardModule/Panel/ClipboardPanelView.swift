import SwiftUI

/// The floating clipboard panel: a header to drag and pin it by, the search, the recent items beside a preview of the
/// selected one. Typing always goes to the search field; arrows, Return, ⌘1 to ⌘9 and Esc are the model's.
struct ClipboardPanelView: View {
    private static let listWidth: CGFloat = 290

    let module: ClipboardModule
    @Bindable var model: ClipboardPanelModel

    @Environment(\.notchAccent) private var accent

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            search
            Divider()
            content
            footer
        }
        .frame(width: ClipboardPanelPlacement.size.width, height: ClipboardPanelPlacement.size.height)
        // Over the list, right under the field.
        .overlay(alignment: .topLeading) {
            if model.suggestions.isOpen {
                ClipboardSuggestionListView(look: .panel, list: model.suggestions) { model.acceptSuggestion(at: $0) }
                    .padding(.top, 72)
                    .padding(.leading, 12)
            }
        }
        .overlay(alignment: .bottom) { noticeView }
        .overlay {
            RoundedRectangle(cornerRadius: ClipboardPanelController.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14))
                .allowsHitTesting(false)
        }
        // While the panel is open: when it appears, then every 2 s, so the hint goes by itself once it is allowed.
        .task {
            while !Task.isCancelled {
                module.refreshAccessibility()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bảng clipboard")
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                    .accessibilityHidden(true)
                Text("Clipboard")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 34)
            // Over the title, which takes no clicks, so the header's whole width drags.
            .overlay { ClipboardPanelDragArea(isEnabled: model.isPinned) { model.moved(to: $0) } }
            stackButton
            Button {
                model.togglePin()
            } label: {
                Image(systemName: model.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(model.isPinned ? accent : Color.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.isPinned ? "Bỏ ghim: bảng đóng sau khi chọn" : "Ghim: giữ bảng mở sau khi chọn và cho phép kéo đi")
            .accessibilityLabel(model.isPinned ? "Bỏ ghim bảng" : "Ghim bảng")
            .accessibilityAddTraits(model.isPinned ? .isSelected : [])
            Button {
                model.requestClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Đóng (Esc)")
            .accessibilityLabel("Đóng bảng")
        }
        .padding(.horizontal, 12)
    }

    /// Starts or stops the copy stack, which the panel can feed and paste from by the shortcuts as usual.
    private var stackButton: some View {
        let stack = module.state.stack
        return Button {
            module.toggleStack()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: stack.isOn ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                if stack.isOn { Text("\(stack.entries.count)").font(.system(size: 11, weight: .semibold).monospacedDigit()) }
            }
            .foregroundStyle(stack.isOn ? accent : Color.secondary)
            .frame(minWidth: 26, minHeight: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(stack.isOn ? "Dừng ngăn xếp và bỏ các mục trong đó" : "Bật ngăn xếp: gom nhiều mục đã chép rồi dán lần lượt")
        .accessibilityLabel(stack.isOn ? "Dừng ngăn xếp, đang có \(stack.entries.count) mục" : "Bật ngăn xếp")
        .accessibilityAddTraits(stack.isOn ? .isSelected : [])
    }

    // MARK: Search

    private var search: some View {
        HStack(spacing: 8) {
            ClipboardSearchField(
                text: $model.searchText, look: .panel, takesFocus: true, focusRequest: 0, onCommand: { model.handleKey($0) }
            )
            .frame(height: 24)
            // The `@` filters the search text holds, as chips that remove them.
            if !model.chips.isEmpty {
                ClipboardSearchChips(look: .panel, tokens: model.chips) { model.removeChip($0) }
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if let message = model.emptyMessage {
            ContentUnavailableView {
                Label(message, systemImage: "doc.on.clipboard")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 0) {
                list
                    .frame(width: Self.listWidth)
                Divider()
                preview
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            // Redraws the relative times each minute.
            TimelineView(.everyMinute) { _ in
                let selected = model.selectedID
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.items) { item in
                            ClipboardPanelRow(
                                item: item, isSelected: item.id == selected, shortcut: model.shortcutNumber(of: item.id),
                                timeLabel: model.timeLabel(for: item), accessibilityLabel: model.accessibilityLabel(for: item),
                                imageURL: imageURL(of: item), thumbnails: model.thumbnails
                            )
                            .id(item.id)
                            .onTapGesture { model.activate(item.id) }
                            .accessibilityAddTraits(item.id == selected ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { model.activate(item.id) }
                        }
                    }
                    .padding(6)
                }
                .scrollIndicators(.never)
            }
            // A selection moved by the keys scrolls only as far as needed; a new search starts at the top.
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
            .onChange(of: model.searchText) {
                if let first = model.items.first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
    }

    @ViewBuilder private var preview: some View {
        if let item = model.selectedItem {
            VStack(alignment: .leading, spacing: 10) {
                ClipboardContentPreview(
                    content: item.content, codeLanguage: item.codeLanguage, imageURL: imageURL(of: item), thumbnails: model.thumbnails,
                    style: .panel
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                Divider()
                HStack(spacing: 6) {
                    if let language = item.codeLanguage {
                        Label(language.title, systemImage: ClipboardSearchTerms.codeSystemImage)
                    } else {
                        Label(item.content.kind.title, systemImage: item.content.kind.systemImage)
                    }
                    Spacer(minLength: 8)
                    ClipboardLibraryAppIcon(item: item, size: 13)
                    Text([item.sourceAppName, model.timeLabel(for: item)].compactMap(\.self).joined(separator: " · "))
                        .lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Xem trước, \(model.accessibilityLabel(for: item))")
        } else {
            Color.clear
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                if module.state.needsAccessibility {
                    ClipboardAccessibilityHint(look: .panel) { module.requestAccessibility() }
                } else {
                    Text("↑↓ chọn  ·  ⏎ dùng  ·  ⌘1–9 chọn nhanh  ·  esc đóng")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
        }
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
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                // A newer notice has a new id, which restarts the wait.
                .task(id: notice.id) {
                    try? await Task.sleep(for: .seconds(1.8))
                    if !Task.isCancelled { model.dismissNotice(notice.id) }
                }
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private func imageURL(of item: ClipboardItem) -> URL? {
        guard case .image = item.content else { return nil }
        return module.fileURLs(of: item).first
    }
}
