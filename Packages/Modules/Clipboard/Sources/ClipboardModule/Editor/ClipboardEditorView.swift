import SwiftUI

/// The editor window's content: the words in a text view, then a bar with the monospaced toggle, the language the words look to be in
/// and the two ways to save. Esc and ⌘W are the window's (`ClipboardEditorWindow`); ⌘S saves as a new item, ⌥⌘S replaces.
struct ClipboardEditorView: View {
    @Bindable var model: ClipboardEditorModel

    var body: some View {
        VStack(spacing: 0) {
            ClipboardEditorTextView(model: model)
            if let notice = model.notice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Divider()
            footer
        }
        .frame(minWidth: 440, minHeight: 280)
        // The alert's own dismissal is ignored: its buttons change the state it shows, as in the library.
        .alert("Bỏ các thay đổi?", isPresented: Binding(get: { model.isConfirmingDiscard }, set: { _ in })) {
            Button("Bỏ thay đổi", role: .destructive) { model.discard() }
            Button("Tiếp tục sửa", role: .cancel) { model.keepEditing() }
        } message: {
            Text("Những gì bạn vừa sửa chưa được lưu.")
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $model.isMonospaced) {
                Label("Chữ đơn cách", systemImage: "textformat.abc.dottedunderline")
            }
            .toggleStyle(.button)
            .help("Dùng chữ có độ rộng đều nhau, hợp với mã")
            if let language = model.detectedLanguage {
                Label(language == .generic ? ClipboardSearchTerms.codeTitle : "\(ClipboardSearchTerms.codeTitle) \(language.title)", systemImage: ClipboardSearchTerms.codeSystemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if model.losesFormatting {
                Text("Định dạng sẽ bị bỏ khi lưu")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Huỷ") { model.cancel() }
                .help("Esc")
            Button("Thay thế mục này") { model.save(.replace) }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(!model.canSave)
                .help("Giữ ngày và nguồn của mục, đánh dấu là đã sửa (⌥⌘S)")
            Button("Lưu thành mục mới") { model.save(.saveAsNew) }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSave)
                .help("Thêm một mục mới, mục gốc giữ nguyên (⌘S)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
