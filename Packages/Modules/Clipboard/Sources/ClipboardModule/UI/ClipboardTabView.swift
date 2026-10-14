import AppKit
import NotchUI
import SwiftUI

/// The Clipboard tab: search, kind and board filters on top, a row of cards below, driven by keyboard or mouse.
struct ClipboardTabView: View {
    static let deniedHint = "MyNotch đang bị chặn đọc clipboard. Cho phép trong Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Dán từ app khác."

    let module: ClipboardModule

    @Environment(\.notch) private var notch
    /// A menu of this app is being tracked, e.g. a card's or a board's context menu.
    @State private var isMenuOpen = false
    @State private var boardEditing: ClipboardBoardEditing?
    @State private var boardName = ""
    /// Bumped to give the search field the keyboard back once a board name is done.
    @State private var searchFocusRequest = 0

    private var state: ClipboardState { module.state }

    /// Menus and the board name field live outside the notch's reach: a click there counts as outside, and the pointer
    /// may leave the notch, so the notch stays pinned while either is shown.
    private var needsPin: Bool { isMenuOpen || boardEditing != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ClipboardSearchField(
                    text: queryBinding(\.text), takesFocus: boardEditing == nil, focusRequest: searchFocusRequest, onCommand: perform
                )
                .frame(minWidth: 140)
                ClipboardKindChips(selection: queryBinding(\.kind))
                libraryButton
            }
            HStack(spacing: 6) {
                ClipboardBoardBar(
                    boards: state.history.boards, selection: queryBinding(\.boardID), editing: boardEditing, name: $boardName,
                    onEdit: startEditing, onFinish: finishEditing, onDelete: { module.deleteBoard($0) }
                )
                // Beside the boards, where there is room: the tab's content height is used up by the rows and the cards.
                if state.needsAccessibility {
                    ClipboardAccessibilityHint(look: .notch) {
                        module.requestAccessibility()
                        // The system's dialog and System Settings come up over the notch, which would close on its own anyway.
                        notch.close()
                    }
                    .fixedSize()
                }
                // With no cards, the empty message already explains it.
                if state.pasteboardDenied, !state.visibleItems.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .help(Self.deniedHint)
                        .accessibilityLabel("Bị chặn đọc clipboard")
                        .accessibilityHint(Self.deniedHint)
                }
            }
            .frame(height: 22)
            cards
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            module.refreshPasteboardAccess()
            // Each open starts from the newest item; the kind and board filters stay as chosen.
            state.query.text = ""
            state.selectedID = nil
        }
        // Menu tracking is one session at a time, submenus included, so a flag is enough. The pin is set right here,
        // not in `onChange`, which could wait until the menu's tracking loop ends.
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            isMenuOpen = true
            notch.setPinned(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)) { _ in
            isMenuOpen = false
            notch.setPinned(boardEditing != nil)
        }
        .onDisappear {
            if needsPin { notch.setPinned(false) }
        }
        // While the tab is shown: when it appears, then every 2 s, so the hint goes by itself once Accessibility is allowed.
        .task {
            while !Task.isCancelled {
                module.refreshAccessibility()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    // MARK: Cards

    @ViewBuilder private var cards: some View {
        let items = state.visibleItems
        if items.isEmpty {
            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(NotchTokens.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .frame(height: ClipboardCardView.size.height)
        } else {
            let selected = ClipboardSelection.current(in: items.map(\.id), selected: state.selectedID)
            let pinned = Set(state.history.boards.flatMap(\.itemIDs))
            ScrollViewReader { proxy in
                // Redraws the relative times each minute. The timeline's date is the start of that minute, so the clock
                // is read instead.
                TimelineView(.everyMinute) { _ in
                    let now = Date.now
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 8) {
                            ForEach(items) { item in
                                card(item, isSelected: item.id == selected, isPinned: pinned.contains(item.id), now: now)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
                .frame(height: ClipboardCardView.size.height)
                // Only a selection the user made scrolls. A new copy changes the implicit first card without moving the
                // row: from the start it shows up in place, elsewhere the user keeps their place.
                .onChange(of: state.selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                }
                .onChange(of: state.query) {
                    if let first = state.visibleItems.first { proxy.scrollTo(first.id, anchor: .leading) }
                }
            }
        }
    }

    private func card(_ item: ClipboardItem, isSelected: Bool, isPinned: Bool, now: Date) -> some View {
        ClipboardCardView(
            item: item, isSelected: isSelected, isPinned: isPinned, now: now,
            imageURL: imageURL(of: item), thumbnails: module.thumbnails
        )
        .onTapGesture { activate(item) }
        .onDrag { startDrag(item) }
        .contextMenu {
            ClipboardCardMenu(module: module, item: item, shownBoardID: state.query.boardID) {
                startEditing(.create(pinning: item.id))
            }
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { activate(item) }
    }

    /// The notch closes behind it, since the window takes the keyboard.
    private var libraryButton: some View {
        Button {
            module.openLibrary()
            notch.close()
        } label: {
            Label("Mở thư viện", systemImage: "rectangle.grid.2x2")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(NotchTokens.secondaryText)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Color.white.opacity(0.06), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Mở thư viện clipboard trong một cửa sổ riêng")
    }

    private var emptyMessage: String {
        let query = state.query
        let hasText = !query.text.allSatisfy(\.isWhitespace)
        if query.boardID != nil, !hasText, query.kind == nil {
            return "Board này chưa có mục nào. Chuột phải vào một thẻ → Ghim vào board."
        }
        if hasText || query.kind != nil || query.boardID != nil { return "Không tìm thấy" }
        return state.pasteboardDenied ? Self.deniedHint : "Chưa có gì trong lịch sử"
    }

    private func imageURL(of item: ClipboardItem) -> URL? {
        guard case .image = item.content else { return nil }
        return module.fileURLs(of: item).first
    }

    // MARK: Actions

    /// Writes only a change; `ClipboardState` then starts the selection from the first card again.
    private func queryBinding<Value: Equatable>(_ keyPath: WritableKeyPath<ClipboardQuery, Value>) -> Binding<Value> {
        Binding(
            get: { state.query[keyPath: keyPath] },
            set: { value in
                if state.query[keyPath: keyPath] != value { state.query[keyPath: keyPath] = value }
            }
        )
    }

    private func perform(_ command: ClipboardKeyCommand) -> Bool {
        let ids = state.visibleItems.map(\.id)
        switch command {
        case .next:
            state.selectedID = ClipboardSelection.next(in: ids, current: state.selectedID)
        case .previous:
            state.selectedID = ClipboardSelection.previous(in: ids, current: state.selectedID)
        case .activate:
            let id = ClipboardSelection.current(in: ids, selected: state.selectedID)
            if let item = state.visibleItems.first(where: { $0.id == id }) { activate(item) }
        case .clearSearch:
            queryBinding(\.text).wrappedValue = ""
        case .close:
            notch.close()
        }
        return true
    }

    private func activate(_ item: ClipboardItem) {
        state.selectedID = item.id
        module.activate(item)
    }

    /// SwiftUI reports no end of a drag, so the notch hears it ended once the mouse button is up again.
    private func startDrag(_ item: ClipboardItem) -> NSItemProvider {
        let notch = notch
        notch.setDragging(true)
        Task {
            repeat {
                try? await Task.sleep(for: .milliseconds(100))
            } while NSEvent.pressedMouseButtons & 1 != 0
            notch.setDragging(false)
        }
        return module.dragProvider(for: item)
    }

    // MARK: Boards

    private func startEditing(_ editing: ClipboardBoardEditing) {
        if case .rename(let id) = editing {
            boardName = state.history.boards.first { $0.id == id }?.name ?? ""
        } else {
            boardName = ""
        }
        boardEditing = editing
        notch.setPinned(true)
    }

    /// Ignores repeats: the field reports the end of editing again when it goes away.
    private func finishEditing(commit: Bool) {
        guard let editing = boardEditing else { return }
        boardEditing = nil
        notch.setPinned(isMenuOpen)
        searchFocusRequest += 1
        guard commit else { return }
        switch editing {
        case .create(let itemID):
            guard let boardID = module.createBoard(named: boardName) else { return }
            if let item = state.history.items.first(where: { $0.id == itemID }) { module.pin(item, to: boardID) }
        case .rename(let id):
            module.renameBoard(id, to: boardName)
        }
    }
}
