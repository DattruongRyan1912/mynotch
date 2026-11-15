import CoreGraphics
import Foundation

/// What the subject lifting flow tells the user, as a short line for an activity beside the notch or a toast.
public enum SubjectLiftMessage: Equatable, Sendable {
    case lifting
    case noSubject
    case lifted
    case failed

    public var text: String {
        switch self {
        case .lifting: "Đang tách chủ thể…"
        case .noSubject: "Không tìm thấy chủ thể"
        case .lifted: "Đã tách & chép chủ thể"
        case .failed: "Không tách được chủ thể"
        }
    }

    public var systemImage: String {
        switch self {
        case .lifting, .noSubject: "person.crop.rectangle"
        case .lifted: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    public var isProcessing: Bool {
        self == .lifting
    }
}

/// Abstract boundary around the machine vision service that lifts foreground subjects from images.
public protocol SubjectLifting: Sendable {
    func liftSubject(from image: CGImage, cropToSubject: Bool) async throws -> CGImage?
}

public struct VisionSubjectLifter: SubjectLifting {
    public init() {}

    public func liftSubject(from image: CGImage, cropToSubject: Bool) async throws -> CGImage? {
        try await SubjectLiftService().liftSubject(from: image, cropToSubject: cropToSubject)
    }
}
