import NotchUI
import SwiftUI

/// The board whose name the tab's inline field is editing.
enum ClipboardBoardEditing: Equatable {
    /// A new board; `pinning` is the card whose menu asked for it, pinned once the board exists.
    case create(pinning: UUID?)
    case rename(UUID)
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

/// Board filter: the whole history, each board (right-click to rename or delete) and "+" for a new one.
/// While a name is edited the inline field stands in for the pill or for "+".
struct ClipboardBoardBar: View {
    let boards: [ClipboardBoard]
    @Binding var selection: UUID?
    let editing: ClipboardBoardEditing?
    @Binding var name: String
    let onEdit: (ClipboardBoardEditing) -> Void
    let onFinish: (_ commit: Bool) -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ClipboardPill(title: "Tất cả", systemImage: "clock", isSelected: selection == nil) { selection = nil }
                ForEach(boards) { board in
                    if editing == .rename(board.id) {
                        nameField
                    } else {
                        ClipboardPill(title: board.name, systemImage: board.systemImage, isSelected: selection == board.id) {
                            selection = board.id
                        }
                        .contextMenu {
                            Button("Đổi tên…", systemImage: "pencil") { onEdit(.rename(board.id)) }
                            Button("Xoá board “\(board.name)”", systemImage: "trash", role: .destructive) { onDelete(board.id) }
                        }
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
