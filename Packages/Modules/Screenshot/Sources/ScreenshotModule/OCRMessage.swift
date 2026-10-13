/// What the OCR flow tells the user, as a short line for an activity beside the notch or a toast.
nonisolated enum OCRMessage: Equatable, Sendable {
    case recognizing
    case noText
    case copied(characters: Int)

    var text: String {
        switch self {
        case .recognizing: "Đang nhận chữ…"
        case .noText: "Không thấy chữ"
        case .copied(let characters): "Đã chép \(characters) ký tự"
        }
    }

    var systemImage: String {
        switch self {
        case .recognizing, .noText: "text.viewfinder"
        case .copied: "doc.on.clipboard.fill"
        }
    }
}
