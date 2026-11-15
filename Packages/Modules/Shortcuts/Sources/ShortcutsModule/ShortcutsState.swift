import Observation

/// What a finished run says, as the activity beside the notch shows it.
enum ShortcutResult: Equatable {
    case ran(name: String)
    case failed(message: String)

    var text: String {
        switch self {
        case .ran(let name): "Đã chạy \(name)"
        case .failed(let message): "Lỗi: \(message)"
        }
    }

    var systemImage: String {
        switch self {
        case .ran: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}

/// What the tab and the Settings rows show. Owned by the module, so it exists whether or not the module runs.
@Observable
final class ShortcutsState {
    /// The last list the CLI gave; kept when a refresh fails.
    var shortcuts: [ShortcutInfo] = []
    var isLoading = false
    var listError: String?
    /// Identifiers being run right now.
    var running: Set<String> = []
    var lastResult: ShortcutResult?
}
