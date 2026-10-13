import Foundation
import ScreenCaptureKit

/// What can go wrong while capturing, reduced to what the module reacts to.
nonisolated enum CaptureError: Error, Equatable, Sendable {
    /// Screen Recording is not granted, or was revoked since the module started.
    case permissionDenied
    case noDisplays
    case failed(String)

    /// Maps ScreenCaptureKit's errors; an error that already is a `CaptureError` stays as it is.
    init(_ error: any Error) {
        if let error = error as? CaptureError {
            self = error
            return
        }
        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain else {
            self = .failed(nsError.localizedDescription)
            return
        }
        switch SCStreamError.Code(rawValue: nsError.code) {
        case .userDeclined: self = .permissionDenied
        case .noDisplayList: self = .noDisplays
        default: self = .failed(nsError.localizedDescription)
        }
    }
}
