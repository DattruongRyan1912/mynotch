import Observation

/// A note under the AI tab's rows that the user dismisses, for what a click could not do and they can fix.
@Observable
final class AgentJumpHint {
    /// Said when macOS has not let MyNotch control the terminal: its app still comes to the front, but not its right tab.
    static let automationDenied = "MyNotch chưa được phép điều khiển ứng dụng terminal, nên chỉ đưa nó lên trước chứ không chọn đúng tab. "
        + "Bật trong Cài đặt hệ thống › Quyền riêng tư & Bảo mật › Tự động hóa."

    var message: String?

    func dismiss() {
        message = nil
    }
}
