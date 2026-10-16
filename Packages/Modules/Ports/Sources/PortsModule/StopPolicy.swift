import Foundation

nonisolated enum StopRefusal: Equatable, Sendable {
    /// pid 0 and 1: the kernel and launchd.
    case launchd
    /// MyNotch itself, or anything inside its bundle.
    case ownApp
    case root
    case otherUser
    /// The system would not say which executable it is, so there is nothing to judge it by.
    case unreadable
    /// Something macOS runs for itself.
    case system

    var message: String {
        switch self {
        case .launchd: "Tiến trình lõi của hệ thống, không thể dừng."
        case .ownApp: "Đây là MyNotch, không thể tự dừng."
        case .root: "Tiến trình của quản trị viên, cần quyền root."
        case .otherUser: "Tiến trình của người dùng khác."
        case .unreadable: "Không đọc được tiến trình này nên không dừng được."
        case .system: "Tiến trình của hệ thống, không dừng từ đây."
        }
    }
}

/// Who may be stopped: only what the user started and what macOS does not need. Run on what was just read, not on the row.
nonisolated struct StopPolicy: Sendable {
    let currentUID: UInt32
    let ownPID: Int32
    /// The `.app` MyNotch runs from; nil when it does not run from one (tests, a plain executable).
    let ownBundlePath: String?

    /// Where macOS keeps its own programs. `/usr/bin` is left out on purpose: `ssh` tunnels, `python3 -m http.server` and `ruby`
    /// are what a developer comes here to stop.
    static let systemPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/bin/", "/Library/Apple/"]

    static var current: StopPolicy {
        let bundle = Bundle.main.bundlePath
        return StopPolicy(currentUID: getuid(), ownPID: getpid(), ownBundlePath: bundle.hasSuffix(".app") ? bundle : nil)
    }

    func refusal(for process: ProcessIdentity) -> StopRefusal? {
        if process.pid <= 1 { return .launchd }
        if process.pid == ownPID { return .ownApp }
        if let path = process.path, let bundle = ownBundlePath, path == bundle || path.hasPrefix(bundle + "/") { return .ownApp }
        if process.uid == 0 || process.realUID == 0 { return .root }
        if process.uid != currentUID || process.realUID != currentUID { return .otherUser }
        guard let path = process.path else { return .unreadable }
        if Self.systemPrefixes.contains(where: path.hasPrefix) { return .system }
        return nil
    }
}
