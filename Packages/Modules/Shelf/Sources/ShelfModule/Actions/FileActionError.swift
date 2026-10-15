import Foundation

/// Why one file could not be processed, in words the result card shows as they are.
nonisolated enum FileActionError: LocalizedError, Equatable, Sendable {
    case missing
    case unreadable
    case notAnImage
    case notPDF
    case pdfLocked
    case pdfEmpty
    case alreadyFormat(ImageFormat)
    case notSmaller
    case encoderUnavailable(ImageFormat)
    case noSubject
    case noText
    case recognitionFailed
    case cutOutFailed
    case cannotWrite
    case zipFailed
    case noImages

    var errorDescription: String? {
        switch self {
        case .missing: "Không tìm thấy file (đã bị chuyển hoặc xoá)"
        case .unreadable: "Không đọc được file"
        case .notAnImage: "Không phải ảnh, hoặc ảnh bị hỏng"
        case .notPDF: "Không phải PDF, hoặc PDF bị hỏng"
        case .pdfLocked: "PDF có mật khẩu"
        case .pdfEmpty: "PDF không có trang nào"
        case .alreadyFormat(let format): "Ảnh đã là \(format.label)"
        case .notSmaller: "Ảnh đã nhỏ hơn mức này"
        case .encoderUnavailable(let format): "Máy này không ghi được \(format.label)"
        case .noSubject: "Không thấy chủ thể để tách"
        case .noText: "Không thấy chữ"
        case .recognitionFailed: "Không nhận được chữ"
        case .cutOutFailed: "Không tách được nền"
        case .cannotWrite: "Không ghi được kết quả cạnh file gốc"
        case .zipFailed: "Không nén được"
        case .noImages: "Không có ảnh nào để gộp"
        }
    }
}

/// A source an action left out, and why. The others were still processed.
nonisolated struct SkippedFile: Sendable, Equatable {
    let source: URL
    let error: FileActionError
}
