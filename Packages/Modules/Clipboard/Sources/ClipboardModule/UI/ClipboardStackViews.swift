import AppKit
import NotchUI
import SwiftUI

/// Starts the copy stack in the Clipboard tab; the stack's own header stops it again.
struct ClipboardStackStartButton: View {
    let module: ClipboardModule

    var body: some View {
        Button {
            module.startStack()
        } label: {
            Label("Ngăn xếp", systemImage: "square.stack.3d.up")
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
        .help("Bật ngăn xếp: gom nhiều mục đã chép rồi dán lần lượt")
    }
}

/// What the Clipboard tab shows while a stack is on: how many items it holds and which one is next, then the items in the
/// order they were copied, to reorder by dragging, remove one by one or clear.
struct ClipboardStackView: View {
    let module: ClipboardModule

    @Environment(\.notch) private var notch
    @State private var dragWatch = ClipboardMouseDragWatch()

    private var stack: CopyStack { module.state.stack }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if stack.entries.isEmpty {
                Text("Chép các mục cần dán, chúng sẽ xếp vào đây theo thứ tự.")
                    .font(.callout)
                    .foregroundStyle(NotchTokens.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Ngăn xếp: \(stack.entries.count) mục", systemImage: "square.stack.3d.up.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(1)
            Text(module.stackOrder.explanation)
                .font(.system(size: 11))
                .foregroundStyle(NotchTokens.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 8)
            ClipboardStackPill(title: "Xoá tất cả", systemImage: "trash") { module.clearStack() }
                .disabled(stack.entries.isEmpty)
            ClipboardStackPill(title: "Dừng", systemImage: "stop.fill") { module.stopStack() }
                .help("Dừng ngăn xếp và bỏ các mục trong đó")
        }
        .frame(height: 22)
    }

    /// A list, for the drag that reorders rows.
    private var list: some View {
        let next = stack.next(module.stackOrder)?.id
        let entries = stack.entries
        return List {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                ClipboardStackRow(
                    entry: entry, isNext: entry.id == next,
                    canMoveUp: index > 0, canMoveDown: index < entries.count - 1,
                    remove: { module.removeFromStack(entry.id) },
                    move: { module.moveInStack(from: IndexSet(integer: index), to: $0 == .up ? index - 1 : index + 2) }
                )
                .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .onMove { module.moveInStack(from: $0, to: $1) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 26)
        // A list's own drag does not say when it starts, so the notch is told while the button is down over the list.
        .onHover { dragWatch.pointerMoved(inside: $0, notch: notch) }
        .onDisappear { dragWatch.stop() }
    }
}

/// One entry of the stack's list.
private struct ClipboardStackRow: View {
    enum Direction { case up, down }

    let entry: CopyStackEntry
    let isNext: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let remove: () -> Void
    let move: (Direction) -> Void

    @State private var isHovered = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.item.content.kind.systemImage)
                .font(.system(size: 11))
                .foregroundStyle(NotchTokens.secondaryText)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(ClipboardCardText.rowTitle(of: entry.item.content))
                .font(.system(size: 12))
                .foregroundStyle(NotchTokens.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isNext {
                Text("Kế tiếp")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NotchTokens.accent)
            }
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(NotchTokens.secondaryText)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Bỏ khỏi ngăn xếp")
            .accessibilityLabel("Bỏ khỏi ngăn xếp")
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Color.white.opacity(isHovered ? 0.12 : 0.07), in: shape)
        .overlay {
            if isNext { shape.strokeBorder(NotchTokens.accent, lineWidth: 1.5) }
        }
        .contentShape(shape)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        // A drag is not the only way to reorder.
        .accessibilityAction(named: "Chuyển lên") { if canMoveUp { move(.up) } }
        .accessibilityAction(named: "Chuyển xuống") { if canMoveDown { move(.down) } }
        .accessibilityAction(named: "Bỏ khỏi ngăn xếp", remove)
    }

    private var accessibilityLabel: String {
        let kind = entry.item.content.kind.title
        let text = ClipboardCardText.summary(of: entry.item.content)
        return (isNext ? [kind, text, "kế tiếp"] : [kind, text]).joined(separator: ", ")
    }
}

/// A small action of the stack's header, drawn like the tab's other pills.
private struct ClipboardStackPill: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(NotchTokens.secondaryText)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Color.white.opacity(0.06), in: Capsule())
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

extension CopyStackOrder {
    /// What the setting means, in the stack's header and in Settings.
    var explanation: String {
        switch self {
        case .firstIn: "Dán từ mục chép trước"
        case .lastIn: "Dán từ mục chép sau"
        }
    }
}

/// Tells the notch a drag is going on while the left button is down after the pointer was over a list, the way the history
/// cards do from their drag. A list's own reordering drag has no start to hook into, so the button is looked at every
/// 50 ms from the moment the pointer enters until it has left and the button is up. A plain click is a drag for a moment,
/// which only keeps the notch from closing for that moment.
@MainActor final class ClipboardMouseDragWatch {
    private var isPointerInside = false
    private var task: Task<Void, Never>?

    func pointerMoved(inside: Bool, notch: NotchHandle) {
        isPointerInside = inside
        guard inside, task == nil else { return }
        task = Task { [self] in
            var wasDown = false
            while !Task.isCancelled {
                let isDown = NSEvent.pressedMouseButtons & 1 != 0
                if isDown != wasDown {
                    notch.setDragging(isDown)
                    wasDown = isDown
                }
                if !isDown, !isPointerInside { break }
                try? await Task.sleep(for: .milliseconds(50))
            }
            // A cancelled watch (the list went away) must not leave the notch in drag mode.
            if wasDown { notch.setDragging(false) }
            if !Task.isCancelled { task = nil }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
