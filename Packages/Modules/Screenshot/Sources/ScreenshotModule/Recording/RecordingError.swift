import Foundation
import ScreenCaptureKit

/// What can go wrong while recording, reduced to what the module reacts to.
nonisolated enum RecordingError: Error, Equatable, Sendable {
    /// Screen Recording is not granted, or was revoked since.
    case screenRecordingDenied
    /// The microphone was asked for and is not granted.
    case microphoneDenied
    case noDisplay
    /// The hardware encoder cannot take the recording's size or format.
    case encoderUnavailable(String)
    /// The file could not be written, for example because the disk is full.
    case writerFailed(String)
    /// The recording ended without a single frame: no file is kept.
    case nothingRecorded
    case alreadyRecording
    /// The system ended the stream: the person used its "stop sharing" control, or the display went away. What was recorded is whole.
    case stoppedBySystem
    case failed(String)

    /// Maps ScreenCaptureKit's errors; an error that already is a `RecordingError` stays as it is.
    init(_ error: any Error) {
        if let error = error as? RecordingError {
            self = error
            return
        }
        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain else {
            self = .failed(nsError.localizedDescription)
            return
        }
        switch SCStreamError.Code(rawValue: nsError.code) {
        case .userDeclined: self = .screenRecordingDenied
        case .failedToStartMicrophoneCapture: self = .microphoneDenied
        case .noDisplayList: self = .noDisplay
        case .userStopped, .systemStoppedStream: self = .stoppedBySystem
        default: self = .failed(nsError.localizedDescription)
        }
    }

    /// One line for a toast, in Vietnamese.
    var message: String {
        switch self {
        case .screenRecordingDenied: "Cần quyền Ghi màn hình để quay"
        case .microphoneDenied: "Cần quyền Micrô để quay có tiếng"
        case .noDisplay: "Không tìm thấy màn hình để quay"
        case .encoderUnavailable: "Máy không mã hoá được video ở kích thước này"
        case .writerFailed: "Không ghi được file quay, có thể ổ đĩa đã đầy"
        case .nothingRecorded: "Chưa quay được khung hình nào"
        case .alreadyRecording: "Đang quay rồi"
        case .stoppedBySystem: "Hệ thống đã dừng quay"
        case .failed: "Không quay được màn hình"
        }
    }
}
