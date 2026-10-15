import AppKit
import NotchUI
import SwiftUI

extension ClipboardLook {
    var primaryText: Color { self == .notch ? NotchTokens.primaryText : .primary }
    var secondaryText: Color { self == .notch ? NotchTokens.secondaryText : .secondary }
}

/// A password field that hides what is typed. In the notch's panel and the floating panel it takes the keyboard as soon as it is
/// shown (the user asked to type), like the board name field; Return and Esc are reported.
struct ClipboardPasswordField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var look: ClipboardLook = .library
    var takesFocus = false
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WindowReportingSecureTextField {
        let field = WindowReportingSecureTextField()
        field.placeholderString = placeholder
        field.stringValue = text
        if look == .notch { field.appearance = NSAppearance(named: .darkAqua) }
        field.bezelStyle = .roundedBezel
        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.focusRingType = .none
        field.delegate = context.coordinator
        if takesFocus {
            field.onWindowChange = { window in
                Task { [weak field] in
                    guard let field, let window else { return }
                    window.makeKey()
                    window.makeFirstResponder(field)
                }
            }
        }
        field.setAccessibilityLabel(placeholder)
        return field
    }

    func updateNSView(_ field: WindowReportingSecureTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ClipboardPasswordField

        init(_ parent: ClipboardPasswordField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch ClipboardKeyCommand(selector, searchIsEmpty: false) {
            case .activate:
                parent.onCommit()
            case .clearSearch, .close:
                parent.onCancel()
            case .next, .previous, .complete, nil:
                return false
            }
            return true
        }
    }
}

/// Reports when SwiftUI puts it in a window.
final class WindowReportingSecureTextField: NSSecureTextField {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

/// What shows over the cards (in the notch) or in a sheet (in the library) for one board: the form that locks it, the prompt that
/// opens it, or the confirmation of taking its lock off or deleting it with its encrypted data.
struct ClipboardBoardVaultView: View {
    enum Mode: Equatable {
        case setUp
        case unlock
        case removeLock
        case deleteData
    }

    let look: ClipboardLook
    let mode: Mode
    let board: ClipboardBoard
    @State private var model: ClipboardBoardLockModel
    let onCancel: () -> Void

    @Environment(\.notchAccent) private var accent

    /// `onDone` runs when the work is done, so whoever shows this can take it away.
    init(module: ClipboardModule, look: ClipboardLook, mode: Mode, board: ClipboardBoard, onDone: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.look = look
        self.mode = mode
        self.board = board
        self.onCancel = onCancel
        let model = module.lockModel(for: board)
        model.onDone = onDone
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            if let confirming = model.confirming {
                confirmation(confirming)
            } else {
                switch mode {
                case .setUp: setUp
                case .unlock: unlock
                case .removeLock, .deleteData: Color.clear.frame(height: 1)
                }
            }
        }
        .font(.system(size: look == .notch ? 11 : 12))
        .foregroundStyle(look.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if mode == .removeLock { model.ask(.removeLock) }
            if mode == .deleteData { model.ask(.deleteData) }
        }
    }

    // MARK: Locking

    private var setUp: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").foregroundStyle(accent)
                Text("Khoá board “\(board.name)”").font(.system(size: look == .notch ? 12 : 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Button("Huỷ", action: onCancel).controlSize(.small)
            }
            HStack(spacing: 6) {
                ClipboardPasswordField(
                    placeholder: "Mật khẩu", text: $model.password, look: look, takesFocus: true, onCommit: {}, onCancel: onCancel
                )
                .frame(minWidth: 110)
                ClipboardPasswordField(
                    placeholder: "Nhập lại mật khẩu", text: $model.confirmation, look: look,
                    onCommit: { Task { await model.lockWithPassword() } }, onCancel: onCancel
                )
                .frame(minWidth: 110)
                Button("Khoá bằng mật khẩu") { Task { await model.lockWithPassword() } }
                    .disabled(!model.canLockWithPassword)
                    .controlSize(.small)
                Button("Dùng Touch ID") { Task { await model.lockWithTouchID() } }
                    .disabled(model.isWorking)
                    .controlSize(.small)
                    .help(ClipboardBoardLockModel.touchIDNote)
            }
            status
            Label(ClipboardBoardLockModel.noRecoveryWarning, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: look == .notch ? 10 : 11))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            if look != .notch {
                Text(ClipboardBoardLockModel.touchIDNote)
                    .font(.caption)
                    .foregroundStyle(look.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Opening

    private var unlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(board.color.color(accent: accent))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Board “\(board.name)” đã khoá").font(.system(size: look == .notch ? 12 : 13, weight: .semibold)).lineLimit(1)
                    Text("\(model.itemCount) mục · nội dung chỉ hiện sau khi mở khoá")
                        .font(.system(size: look == .notch ? 10 : 11))
                        .foregroundStyle(look.secondaryText)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                if model.method == .touchID {
                    Button("Mở khoá bằng Touch ID") { Task { await model.unlockWithTouchID() } }
                        .disabled(model.isWorking)
                        .controlSize(.small)
                } else {
                    ClipboardPasswordField(
                        placeholder: "Mật khẩu", text: $model.password, look: look, takesFocus: true,
                        onCommit: { Task { await model.unlockWithPassword() } }, onCancel: onCancel
                    )
                    .frame(width: 180)
                    Button("Mở khoá") { Task { await model.unlockWithPassword() } }
                        .disabled(!model.canUnlockWithPassword)
                        .controlSize(.small)
                }
                Spacer(minLength: 0)
                Button("Quên mật khẩu? Xoá board…") { model.ask(.deleteData) }
                    .buttonStyle(.link)
                    .controlSize(.small)
                    .font(.system(size: look == .notch ? 10 : 11))
            }
            status
        }
    }

    // MARK: Confirming

    private func confirmation(_ confirming: ClipboardBoardLockModel.Confirmation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch confirming {
            case .deleteData:
                Label(
                    "Xoá board “\(board.name)” cùng \(model.itemCount) mục đã mã hoá? Không có cách lấy lại.",
                    systemImage: "trash.fill"
                )
                .foregroundStyle(.red)
                HStack {
                    Button("Xoá board và dữ liệu", role: .destructive) { Task { await model.confirm() } }
                    Button("Giữ lại") { model.cancelConfirmation(); if mode != .unlock { onCancel() } }
                }
            case .removeLock:
                Label(
                    "Gỡ khoá board “\(board.name)”? Các mục sẽ nằm trong lịch sử như bình thường và không còn được mã hoá.",
                    systemImage: "lock.open.fill"
                )
                HStack {
                    Button("Gỡ khoá") { Task { await model.confirm() } }
                    Button("Huỷ") { model.cancelConfirmation(); onCancel() }
                }
            }
            status
        }
        .controlSize(.small)
    }

    @ViewBuilder private var status: some View {
        if model.isWorking {
            ProgressView().controlSize(.small)
        } else if let message = model.failureMessage ?? model.problem {
            Label(message, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(model.failureMessage != nil ? Color.red : Color.orange)
                .font(.system(size: look == .notch ? 10 : 11))
        }
    }
}

/// The lock entries of a board's context menu in the library: lock it, open it, close it again, or take the lock off.
struct ClipboardBoardLockMenu: View {
    let board: ClipboardBoard
    /// Selects the board, where the prompt that opens it is.
    let onSelect: () -> Void
    let onVault: (ClipboardVaultPrompt) -> Void
    let onRelock: (UUID) -> Void

    var body: some View {
        if board.isLocked {
            Button("Mở khoá…", systemImage: "lock.open", action: onSelect)
        } else if board.isProtected {
            Button("Khoá lại ngay", systemImage: "lock") { onRelock(board.id) }
            Button("Gỡ khoá…", systemImage: "lock.slash") { onVault(.removeLock(board.id)) }
        } else {
            Button("Khoá board…", systemImage: "lock") { onVault(.lock(board.id)) }
        }
    }
}
