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
            .disabled(backup.isBusy || !isAvailable)
        }
        .sheet(isPresented: $showsOptions) {
            ClipboardBackupOptionsSheet(
                legacyTextCount: { backup.legacyTextCount(for: $0) },
                lockedBoardCount: backup.lockedBoardCount(),
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
            // A restore that has been read waits here, with nothing written, for the user to say how to do it. On another row
            // than the backup sheet, which a view can only show one of at a time.
            .sheet(isPresented: Binding(get: { backup.choosingSummary != nil }, set: { _ in })) {
                if let summary = backup.choosingSummary {
                    ClipboardRestorePlanSheet(
                        summary: summary,
                        onChoose: { backup.confirmRestore($0) },
                        onCancel: { backup.declineRestore() }
                    )
                }
            }
    }

    @ViewBuilder private var status: some View {
        switch backup.status {
        case .idle, .choosing:
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

/// What goes in a backup: how much of the history, and whether secrets may. Secrets stay out only as far as they are known to be
/// secrets, which the sheet says, so ticking the box is never taken for a promise.
struct ClipboardBackupOptionsSheet: View {
    /// How many texts of a scope were saved before MyNotch tracked secrets (see `ClipboardBackupWriter.legacyTextCount`).
    let legacyTextCount: (ClipboardBackupOptions.Scope) -> Int
    /// How many boards have a lock, which the box offers to include; 0 hides it.
    var lockedBoardCount = 0
    let onChoose: (ClipboardBackupOptions) -> Void
    let onCancel: () -> Void

    /// Under the box, which is ticked: what it does and does not cover. Never a promise that nothing private is left.
    static let skipCaption = "Chỉ những mục mà app đánh dấu là bí mật lúc chép (mật khẩu, mã tạm thời) mới được bỏ qua. Mục không được đánh dấu vẫn nằm trong tệp."

    /// For texts saved before MyNotch tracked which copies are secrets, which are in the file whatever the box says.
    static func legacyWarning(_ count: Int) -> String {
        "\(count) mục văn bản được lưu trước khi MyNotch biết đánh dấu mục nhạy cảm, nên không nhận ra được và vẫn nằm trong tệp, kể cả khi đã bỏ qua mục nhạy cảm. Mật khẩu có thể nằm trong số đó."
    }

    /// Under the box for boards that have a lock, which is not ticked: they are not in the file at all, name included.
    static let lockedLeftOutCaption = "Board đã khoá không nằm trong tệp, kể cả tên của nó."
    /// When it is: each goes in as the encrypted file it is, and only its own password opens it, wherever the file goes.
    static let lockedIncludedCaption = "Mỗi board đã khoá vẫn được mã hoá trong tệp và cần mật khẩu của chính nó để mở: nếu quên mật khẩu thì không có cách lấy lại. Board dùng Touch ID chỉ mở được trên máy này nên không đưa vào tệp."

    @State private var options = ClipboardBackupOptions()

    var body: some View {
        let legacy = legacyTextCount(options.scope)
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
                    Text(Self.skipCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Mục nhạy cảm sẽ nằm trong tệp mà không được mã hoá. Hãy cất tệp ở nơi an toàn.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if legacy > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Label(Self.legacyWarning(legacy), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    if options.scope == .allHistory {
                        Button("Chỉ xuất mục đã ghim và board") { options.scope = .pinnedOnly }
                            .controlSize(.small)
                    }
                }
            }
            if lockedBoardCount > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Gồm cả \(lockedBoardCount) board đã khoá", isOn: $options.includeLockedBoards)
                    Text(options.includeLockedBoards ? Self.lockedIncludedCaption : Self.lockedLeftOutCaption)
                        .font(.caption)
                        .foregroundStyle(options.includeLockedBoards ? .orange : .secondary)
                }
            }
            Text("Mục file chỉ lưu đường dẫn nên có thể không khôi phục được trên máy khác. Tệp được lưu chỉ cho riêng bạn đọc, nhưng không được mã hoá.")
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
        .frame(width: 440)
    }
}

/// What a restore would do to the history under the limits, shown before it does anything, with the ways to go on: keep
/// everything it brings (and everything that is there), follow the limits as they are, or not restore.
struct ClipboardRestorePlanSheet: View {
    let summary: ClipboardRestorePlanSummary
    let onChoose: (ClipboardRestorePolicy) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Khôi phục từ tệp sao lưu")
                .font(.headline)
            Text(Self.overview(summary))
            if summary.affectsHistory {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Với giới hạn lịch sử trong Cài đặt (số mục, thời gian giữ, dung lượng ảnh):")
                    ForEach(Self.consequences(summary), id: \.self) { line in
                        Label(line, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            Text("Chưa có gì được ghi cho đến khi bạn chọn.")
                .font(.caption)
                .foregroundStyle(.secondary)
            choices
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(width: 460)
    }

    @ViewBuilder private var choices: some View {
        if summary.affectsHistory {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Button("Giữ tất cả") { onChoose(.keepAll) }
                        .keyboardShortcut(.defaultAction)
                    Text("Mục khôi phục không bị giới hạn dọn đi, mục đang có được giữ nguyên.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Button("Theo giới hạn hiện tại") { onChoose(.applyLimits) }
                    Text("Áp dụng đúng các con số ở trên.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Huỷ", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        } else {
            HStack {
                Spacer()
                Button("Huỷ", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Khôi phục") { onChoose(.applyLimits) }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// "Tệp có 312 mục mới, 18 mục trùng lặp sẽ bị bỏ qua, tạo 2 board mới."
    static func overview(_ summary: ClipboardRestorePlanSummary) -> String {
        var parts = ["Tệp có \(summary.added) mục mới"]
        if summary.duplicates > 0 { parts.append("\(summary.duplicates) mục trùng lặp sẽ bị bỏ qua") }
        if summary.unreadable > 0 { parts.append("\(summary.unreadable) mục không đọc được") }
        if summary.boardsToCreate > 0 { parts.append("\(summary.boardsToCreate) board mới sẽ được tạo") }
        if summary.lockedBoards > 0 { parts.append("\(summary.lockedBoards) board đã khoá sẽ được khôi phục (mở bằng mật khẩu của nó)") }
        return parts.joined(separator: ", ") + "."
    }

    /// What the limits would take, one line each.
    static func consequences(_ summary: ClipboardRestorePlanSummary) -> [String] {
        var lines: [String] = []
        if summary.outsideLimits > 0 {
            lines.append("\(summary.outsideLimits) mục vừa khôi phục sẽ bị dọn ngay, vì quá cũ hoặc vượt giới hạn.")
        }
        if summary.evictedExisting > 0 {
            var line = "\(summary.evictedExisting) mục đang có sẽ bị xoá để lấy chỗ"
            if summary.evictedExistingImages > 0 { line += ", trong đó \(summary.evictedExistingImages) ảnh (tệp ảnh cũng bị xoá)" }
            lines.append(line + ".")
        }
        return lines
    }
}
