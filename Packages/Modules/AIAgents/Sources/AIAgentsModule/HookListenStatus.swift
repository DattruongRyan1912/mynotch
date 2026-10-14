import Observation

/// Whether the socket for the hook helper could be opened, which the Settings rows show. The module is not
/// observable itself, and a socket that stays closed would otherwise look like hooks that nothing sends.
@Observable
final class HookListenStatus {
    static let failureMessage = "Không mở được socket nhận hook nên trạng thái chính xác chưa hoạt động. Tắt rồi bật lại để thử lại."

    static let permissionFailureMessage = "Không mở được socket duyệt quyền nên nút Cho phép và Từ chối chưa hoạt động. Tắt rồi bật lại \"Trạng thái chính xác\" để thử lại."

    /// Set while the socket is wanted but could not be opened; nil otherwise.
    var failure: String?
}
