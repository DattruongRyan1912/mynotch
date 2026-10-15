import NotchUI
import SwiftUI

/// What the tab's row of boards is doing besides listing them.
enum ClipboardBoardEditing: Equatable {
    /// A new board; `pinning` is the card whose menu asked for it, pinned once the board exists.
    case create(pinning: UUID?)
    /// The inline field is changing this board's name.
    case rename(UUID)
    /// The strip of icons and colours stands in for the row, for this board.
    case style(UUID)
}

/// Kind filter: all items or one kind. Choosing the selected kind again shows all items.
struct ClipboardKindChips: View {
    @Binding var selection: ClipboardKind?

    var body: some View {
        HStack(spacing: 2) {
            ClipboardPill(title: "Tất cả", isSelected: selection == nil) { selection = nil }
            ForEach(ClipboardKind.allCases, id: \.self) { kind in
                ClipboardPill(title: kind.title, isSelected: selection == kind) {
                    selection = selection == kind ? nil : kind
                }
            }
        }
        .fixedSize()
    }
}

/// Board filter: the whole history, each board (right-click to rename, restyle, move or delete; drag to reorder) and "+" for
/// a new one. While a name is edited the inline field stands in for the pill or for "+", and while a board's look is chosen
/// the strip of icons and colours stands in for the whole row.
struct ClipboardBoardBar: View {
    private static let spacing: CGFloat = 4

    let boards: [ClipboardBoard]
    @Binding var selection: UUID?
    let editing: ClipboardBoardEditing?
    @Binding var name: String
    let onEdit: (ClipboardBoardEditing) -> Void
    let onFinish: (_ commit: Bool) -> Void
    let onDelete: (UUID) -> Void
    /// A board dragged to this index of the row.
    let onMove: (UUID, Int) -> Void
    /// A board moved one step along the row, from its menu or VoiceOver.
    let onStep: (UUID, Int) -> Void
    let onIcon: (UUID, String) -> Void
    let onColor: (UUID, ClipboardBoardColor) -> Void
    /// What the lock menu items ask for; the tab shows the form or prompt.
    var onVault: (ClipboardVaultPrompt) -> Void = { _ in }
    /// "Khoá lại ngay" on an open board.
    var onRelock: (UUID) -> Void = { _ in }

    @Environment(\.notch) private var notch
    @State private var widths: [UUID: CGFloat] = [:]
    @State private var drag: BoardDrag?

    /// A pill that is being dragged and how far it has gone.
    struct BoardDrag: Equatable {
        let id: UUID
        var translation: CGFloat
    }

    var body: some View {
        if case .style(let id) = editing, let board = boards.first(where: { $0.id == id }) {
            ClipboardBoardStyleStrip(
                board: board, onIcon: { onIcon(id, $0) }, onColor: { onColor(id, $0) }, onDone: { onFinish(true) }
            )
        } else {
            row
        }
    }

    private var row: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Self.spacing) {
                ClipboardPill(title: "Tất cả", systemImage: "clock", isSelected: selection == nil) { selection = nil }
                ForEach(Array(boards.enumerated()), id: \.element.id) { index, board in
                    if editing == .rename(board.id) {
                        nameField
                    } else {
                        pill(board, at: index)
                    }
                }
                if case .create = editing {
                    nameField
                } else {
                    addButton
                }
            }
        }
        .scrollIndicators(.never)
        .onDisappear { endDrag() }
    }

    private func pill(_ board: ClipboardBoard, at index: Int) -> some View {
        let isDragged = drag?.id == board.id
        return ClipboardBoardPill(board: board, isSelected: selection == board.id)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { widths[board.id] = $0 }
            .offset(x: isDragged ? drag?.translation ?? 0 : 0)
            .opacity(isDragged ? 0.8 : 1)
            .zIndex(isDragged ? 1 : 0)
            .onTapGesture { selection = board.id }
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        if drag == nil { notch.setDragging(true) }
                        drag = BoardDrag(id: board.id, translation: value.translation.width)
                    }
                    .onEnded { value in
                        let target = ClipboardBoardReorder.destination(
                            of: index, translation: value.translation.width, widths: boards.map { widths[$0.id] ?? 60 }, spacing: Self.spacing
                        )
                        endDrag()
                        if target != index { onMove(board.id, target) }
                    }
            )
            .contextMenu {
                Button("Đổi tên…", systemImage: "pencil") { onEdit(.rename(board.id)) }
                Button("Đổi biểu tượng và màu…", systemImage: "paintpalette") { onEdit(.style(board.id)) }
                Button("Chuyển sang trái", systemImage: "arrow.left") { onStep(board.id, -1) }
                    .disabled(index == 0)
                Button("Chuyển sang phải", systemImage: "arrow.right") { onStep(board.id, 1) }
                    .disabled(index == boards.count - 1)
                Divider()
                if board.isLocked {
                    Button("Mở khoá…", systemImage: "lock.open") { selection = board.id }
                } else if board.isProtected {
                    Button("Khoá lại ngay", systemImage: "lock") { onRelock(board.id) }
                    Button("Gỡ khoá…", systemImage: "lock.slash") { onVault(.removeLock(board.id)) }
                } else {
                    Button("Khoá board…", systemImage: "lock") { onVault(.lock(board.id)) }
                }
                Divider()
                if board.isProtected {
                    Button("Xoá board “\(board.name)” và dữ liệu đã mã hoá…", systemImage: "trash", role: .destructive) {
                        onVault(.deleteData(board.id))
                    }
                } else {
                    Button("Xoá board “\(board.name)”", systemImage: "trash", role: .destructive) { onDelete(board.id) }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selection == board.id ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { selection = board.id }
            // A drag is not the only way to reorder.
            .accessibilityAction(named: "Chuyển sang trái") { if index > 0 { onStep(board.id, -1) } }
            .accessibilityAction(named: "Chuyển sang phải") { if index < boards.count - 1 { onStep(board.id, 1) } }
            .accessibilityAction(named: "Đổi biểu tượng và màu") { onEdit(.style(board.id)) }
    }

    /// The notch hears when the drag ends, which keeps it open while the pointer is out of it.
    private func endDrag() {
        guard drag != nil else { return }
        drag = nil
        notch.setDragging(false)
    }

    private var nameField: some View {
        ClipboardBoardNameField(name: $name, onCommit: { onFinish(true) }, onCancel: { onFinish(false) })
            .frame(width: 120)
    }

    private var addButton: some View {
        Button { onEdit(.create(pinning: nil)) } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NotchTokens.secondaryText)
                .frame(width: 22, height: 22)
                .background(Color.white.opacity(0.06), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Board mới")
    }
}

/// A filter choice, styled like the notch's tab bar.
struct ClipboardPill: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .foregroundStyle(isSelected ? NotchTokens.primaryText : NotchTokens.secondaryText)
            .background(isSelected ? Color.white.opacity(0.14) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

nonisolated extension ClipboardKind {
    /// Label of the kind's filter chip.
    var title: String {
        switch self {
        case .text: "Văn bản"
        case .link: "Link"
        case .image: "Ảnh"
        case .file: "File"
        case .color: "Màu"
        }
    }
}
