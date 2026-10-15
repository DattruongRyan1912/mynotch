import ClipboardMCPKit
import SwiftUI

/// What the rows need from the module: its state, the helper's path for the snippets, and the two things a button does.
struct ClipboardMCPActions {
    let state: ClipboardMCPState
    /// Where the agents' configuration is to find the helper.
    let helperPath: String
    /// Puts text on the pasteboard, which the "Sao chép" buttons use.
    let copy: (String) -> Void
    /// "Tắt ngay": off, and the socket closed before it returns.
    let turnOff: () -> Void
}

/// The "AI agent đọc lịch sử clipboard" rows of the Clipboard settings: the switch, and while it is on, the lines to add to each
/// agent's configuration, what the agents asked for lately, and a button that turns it off at once. MyNotch never edits an
/// agent's own files; the user pastes the lines.
struct ClipboardMCPRows: View {
    static let explanation = "Agent như Claude Code, Cursor hay Codex tìm trong lịch sử clipboard ngay trên máy này, qua một cổng nội bộ chỉ tài khoản của bạn mở được, không qua mạng. MyNotch cố gắng ẩn mục nhạy cảm và mục trông giống mật khẩu hoặc khoá; đừng bật nếu clipboard của bạn chứa bí mật quan trọng. Ảnh chỉ được tả kích thước, tệp chỉ có tên. Mặc định tắt."
    static let addNote = "MyNotch không tự sửa file cấu hình của agent: bạn thêm đoạn dưới đây rồi khởi động lại agent."
    static let logNote = "Chỉ ghi giờ, công cụ và số kết quả, không ghi nội dung tìm kiếm. Nhật ký mất khi thoát MyNotch."
    static let notRunning = "Module Clipboard đang tắt: bật nó để agent truy vấn được."

    let isOn: Binding<Bool>
    let actions: ClipboardMCPActions
    /// Whether the module runs, which the socket needs.
    let isRunning: Bool

    var body: some View {
        Toggle(isOn: isOn) {
            Text(ClipboardMCPMessages.settingName)
            Text(Self.explanation)
        }
        if isOn.wrappedValue {
            status
            let snippets = ClipboardMCPSnippets(helperPath: actions.helperPath)
            Text(Self.addNote)
                .font(.caption)
                .foregroundStyle(.secondary)
            snippet("Claude Code", note: "Chạy trong terminal:", text: snippets.claudeCode)
            snippet("Cursor", note: "Thêm vào \(ClipboardMCPSnippets.cursorFile) (đã có file thì thêm mục này vào \"mcpServers\"):", text: snippets.cursor)
            snippet("Codex", note: "Thêm vào \(ClipboardMCPSnippets.codexFile):", text: snippets.codex)
            ClipboardMCPLogRows(state: actions.state)
            Button("Tắt ngay", role: .destructive, action: actions.turnOff)
        }
    }

    @ViewBuilder private var status: some View {
        if !isRunning {
            Text(Self.notRunning)
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if let failure = actions.state.listenFailure {
            Text(failure)
                .font(.caption)
                .foregroundStyle(.red)
        }
        if let failure = actions.state.helperFailure {
            Text("Không đặt được công cụ cho agent: \(failure)")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func snippet(_ title: String, note: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Button("Sao chép") { actions.copy(text) }
        }
    }
}

/// The last calls the agents made, newest first.
private struct ClipboardMCPLogRows: View {
    let state: ClipboardMCPState

    var body: some View {
        DisclosureGroup("Nhật ký truy cập (\(state.entries.count) lần gần nhất)") {
            if state.entries.isEmpty {
                Text("Chưa có agent nào truy vấn.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.entries) { entry in
                    HStack {
                        Text(entry.date, format: .dateTime.day().month().hour().minute().second())
                            .monospacedDigit()
                        Text(entry.tool)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(entry.summary)
                    }
                }
                Button("Xoá nhật ký") { state.clearLog() }
            }
            Text(ClipboardMCPRows.logNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
