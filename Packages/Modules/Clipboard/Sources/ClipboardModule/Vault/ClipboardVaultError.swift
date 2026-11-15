import Foundation

/// Why locking, unlocking or changing a locked board did not happen. The messages are what the user reads, and say nothing
/// of keys or passwords.
nonisolated enum ClipboardVaultError: Error, Equatable, LocalizedError, Sendable {
    case moduleStopped
    case boardNotFound
    /// The board has a lock already.
    case alreadyLocked
    /// The board has no lock.
    case notLocked
    /// The board has to be unlocked first.
    case stillLocked
    /// Another lock or unlock of this board is under way.
    case busy
    case passwordTooShort
    /// A password was given for a Touch ID board, or the reverse.
    case wrongMethod
    /// The password does not open the board (or the key stored with it is damaged: the two cannot be told apart).
    case wrongPassword
    /// The encrypted data does not pass its check: damaged or changed.
    case damaged
    case unsupportedVersion(Int)
    /// The user dismissed the Touch ID or password prompt.
    case cancelled
    /// Touch ID and the device password could not be asked for, or did not accept the user.
    case authenticationFailed
    /// The key this Mac kept for the board is not in the Keychain any more.
    case keyMissing
    /// The Keychain refused, with its status code (a missing entitlement, a locked keychain, …).
    case keychain(Int32)
    case cannotWrite(String)
    case cannotRead(String)
    /// Touch ID cannot be used here: the Keychain has no access group for this build, or this Mac cannot ask for it.
    case touchIDUnavailable
    /// Too many wrong passwords in a row: no more tries for this many seconds.
    case tooManyAttempts(retryAfter: Int)
    /// The board's sealed file would be bigger than the format allows, and could never be opened.
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .moduleStopped: "Hãy bật module Clipboard rồi thử lại."
        case .boardNotFound: "Không tìm thấy board này."
        case .alreadyLocked: "Board này đã có khoá."
        case .notLocked: "Board này chưa có khoá."
        case .stillLocked: "Hãy mở khoá board trước."
        case .busy: "Board này đang được xử lý, thử lại sau giây lát."
        case .wrongMethod: "Board này dùng cách mở khoá khác."
        case .passwordTooShort: "Mật khẩu cần ít nhất \(ClipboardVaultPolicy.minimumPasswordLength) ký tự."
        case .wrongPassword: "Sai mật khẩu."
        case .damaged: "Dữ liệu đã mã hoá của board bị hỏng hoặc đã bị sửa nên không mở được."
        case .unsupportedVersion: "Board này được khoá bởi bản MyNotch mới hơn. Hãy cập nhật MyNotch rồi mở khoá."
        case .cancelled: "Đã huỷ."
        case .authenticationFailed: "Không xác thực được bằng Touch ID hoặc mật khẩu máy."
        case .keyMissing: "Khoá của board không còn trong Keychain của máy này nên không thể mở."
        case .keychain(let status) where status == -34018:
            "MyNotch chưa được phép dùng Keychain cho Touch ID (thiếu quyền keychain-access-groups). Hãy dùng mật khẩu."
        case .keychain: "Keychain từ chối thao tác. Hãy dùng mật khẩu thay cho Touch ID."
        case .touchIDUnavailable: "Touch ID cần bản MyNotch có hồ sơ ký; hiện dùng mật khẩu."
        case .tooManyAttempts(let seconds): "Đã nhập sai nhiều lần. Thử lại sau \(seconds) giây."
        case .tooLarge: "Board quá lớn để khoá (tối đa 1 GB sau khi mã hoá). Hãy bớt mục hoặc ảnh rồi thử lại."
        case .cannotWrite: "Không ghi được dữ liệu đã mã hoá của board."
        case .cannotRead: "Không đọc được dữ liệu đã mã hoá của board."
        }
    }
}

/// What a password for a locked board has to be.
nonisolated enum ClipboardVaultPolicy {
    static let minimumPasswordLength = 10

    /// At least ten characters (not bytes) that are not all blank.
    static func isAcceptable(_ password: String) -> Bool {
        password.count >= minimumPasswordLength && !password.allSatisfy(\.isWhitespace)
    }
}
