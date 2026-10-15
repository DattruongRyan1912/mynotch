import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The "Sao lưu và khôi phục" rows of the Clipboard settings: two buttons, then what the work in progress or the last one
/// says. Backup asks first what to put in the file; restore goes straight to choosing it.
struct ClipboardBackupRows: View {
    /// A type the system does not know, which stands for the extension; it still opens as a zip.
    static let contentType = UTType(filenameExtension: ClipboardBackupFormat.fileExtension, conformingTo: .zip) ?? .zip

    let backup: ClipboardBackupModel
    /// False while the module is stopped, since there is no history then to save or to add to.
    let isAvailable: Bool

    @State private var showsOptions = false

    var body: some View {
        LabeledContent("Sao lưu và khôi phục") {
            HStack {
                Button("Sao lưu…") { showsOptions = true }
                Button("Khôi phục…", action: chooseFileToRestore)
            }
            .disabled(backup.isWorking || !isAvailable)
        }
        .sheet(isPresented: $showsOptions) {
            ClipboardBackupOptionsSheet(
                onChoose: { options in
                    showsOptions = false
                    // The save panel waits until the sheet is gone.
                    Task { chooseDestination(options) }
                },
                onCancel: { showsOptions = false }
            )
        }
        status
        Text(isAvailable
            ? "Tệp .mynotchclip gồm lịch sử, ảnh, board cùng biểu tượng và thứ tự của chúng. Khôi phục gộp vào lịch sử hiện có, không tạo mục trùng."
            : "Bật module Clipboard để sao lưu hoặc khôi phục.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder private var status: some View {
        switch backup.status {
        case .idle:
            EmptyView()
        case .working(let title, let fraction):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                    Spacer()
                    Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button("Huỷ") { backup.cancel() }
                }
                ProgressView(value: fraction)
                    .accessibilityLabel(title)
            }
        case .finished(let text):
            message(text, systemImage: "checkmark.circle.fill", tint: .green)
        case .failed(let text):
            message(text, systemImage: "exclamationmark.triangle.fill", tint: .orange)
        case .cancelled:
            message("Đã huỷ.", systemImage: "xmark.circle", tint: .secondary)
        }
    }

    private func message(_ text: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label {
                Text(text).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: systemImage).foregroundStyle(tint)
            }
            Spacer()
            Button("Đóng") { backup.dismiss() }
                .buttonStyle(.borderless)
        }
    }

    // MARK: Panels

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func chooseDestination(_ options: ClipboardBackupOptions) {
        let panel = NSSavePanel()
        panel.title = "Sao lưu clipboard"
        panel.prompt = "Sao lưu"
        panel.nameFieldStringValue = "MyNotch Clipboard \(Self.dayFormatter.string(from: .now)).\(ClipboardBackupFormat.fileExtension)"
        panel.allowedContentTypes = [Self.contentType]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        backup.startExport(options, to: url)
    }

    private func chooseFileToRestore() {
        let panel = NSOpenPanel()
        panel.title = "Khôi phục clipboard"
        panel.prompt = "Khôi phục"
        panel.allowedContentTypes = [Self.contentType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        backup.startRestore(from: url)
    }
}

/// What goes in a backup: how much of the history, and whether secrets may. Secrets stay out unless this is unticked.
struct ClipboardBackupOptionsSheet: View {
    let onChoose: (ClipboardBackupOptions) -> Void
    let onCancel: () -> Void

    @State private var options = ClipboardBackupOptions()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sao lưu clipboard")
                .font(.headline)
            Picker("Phạm vi", selection: $options.scope) {
                Text("Toàn bộ lịch sử").tag(ClipboardBackupOptions.Scope.allHistory)
                Text("Chỉ mục đã ghim và board").tag(ClipboardBackupOptions.Scope.pinnedOnly)
            }
            .pickerStyle(.radioGroup)
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Bỏ qua mục nhạy cảm", isOn: $options.skipSensitive)
                if options.skipSensitive {
                    Text("Mật khẩu và mã tạm thời mà app đánh dấu là bí mật sẽ không được ghi vào tệp.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Mục nhạy cảm sẽ nằm trong tệp mà không được mã hoá. Hãy cất tệp ở nơi an toàn.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Text("Mục file chỉ lưu đường dẫn nên có thể không khôi phục được trên máy khác.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Huỷ", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Chọn nơi lưu…") { onChoose(options) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(width: 420)
    }
}
