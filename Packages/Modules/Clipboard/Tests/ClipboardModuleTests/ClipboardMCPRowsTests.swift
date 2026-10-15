import AppKit
import ClipboardMCPKit
import SwiftUI
import Testing
@testable import ClipboardModule

/// The Settings rows for agents. The window is checked by eye; here, the words that carry the promise, and that the rows are
/// built for each state without being clicked (the buttons write to the real pasteboard, so no test presses them).
@Suite struct ClipboardMCPRowsTests {
    func rows(isOn: Bool, isRunning: Bool = true, entries: Int = 0, failure: String? = nil) -> some View {
        let state = ClipboardMCPState()
        for index in 0..<entries { state.record(tool: "search_clipboard", outcome: .answered(count: index), at: Date(timeIntervalSince1970: 1_800_000_000)) }
        state.listenFailure = failure
        let actions = ClipboardMCPActions(state: state, helperPath: "/x/bin/mynotch-clipboard-mcp", copy: { _ in }, turnOff: {})
        return Form {
            ClipboardMCPRows(isOn: .constant(isOn), actions: actions, isRunning: isRunning)
        }
        .formStyle(.grouped)
        .frame(width: 520)
    }

    func height(of view: some View) -> CGFloat {
        NSHostingView(rootView: view).fittingSize.height
    }

    @Test func theSwitchIsNamedAsTheBriefSaysAndTheCopyIsHonest() {
        #expect(ClipboardMCPMessages.settingName == "Cho AI agent đọc lịch sử clipboard (MCP)")
        let words = ClipboardMCPRows.explanation
        #expect(words.contains("không qua mạng"))
        #expect(words.contains("MyNotch cố gắng ẩn mục nhạy cảm và mục trông giống mật khẩu hoặc khoá; đừng bật nếu clipboard của bạn chứa bí mật quan trọng."))
        // Nothing is promised that the filter cannot keep.
        #expect(!words.contains("không bao giờ"))
        #expect(words.contains("tệp chỉ có tên"))
        #expect(words.contains("Mặc định tắt"))
        #expect(ClipboardMCPRows.addNote.contains("không tự sửa file cấu hình"))
        #expect(ClipboardMCPRows.logNote.contains("không ghi nội dung tìm kiếm"))
    }

    @Test func offShowsOnlyTheSwitchAndOnShowsTheSnippetsLogAndTheOffButton() {
        let off = height(of: rows(isOn: false))
        let on = height(of: rows(isOn: true))
        #expect(off > 0)
        #expect(on > off + 150)
    }

    @Test func aStoppedModuleOrAFailureAddsALineExplainingIt() {
        let plain = height(of: rows(isOn: true))
        #expect(height(of: rows(isOn: true, isRunning: false)) > plain)
        #expect(height(of: rows(isOn: true, failure: "Không mở được cổng")) > plain)
    }

    @Test func theLogRowsBuildWithEntries() {
        #expect(height(of: rows(isOn: true, entries: 50)) > 0)
    }
}
