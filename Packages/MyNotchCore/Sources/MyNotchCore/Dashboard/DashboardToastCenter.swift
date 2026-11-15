import Foundation
import Observation

public struct DashboardToast: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let message: String
    public let systemImage: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        message: String,
        systemImage: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.message = message
        self.systemImage = systemImage
        self.createdAt = createdAt
    }
}

@Observable
@MainActor
public final class DashboardToastCenter {
    public static let shared = DashboardToastCenter()

    public private(set) var currentToast: DashboardToast?
    private var dismissTask: Task<Void, Never>?

    public init() {}

    public func show(message: String, systemImage: String? = nil, duration: Double = 2.5) {
        dismissTask?.cancel()
        let toast = DashboardToast(message: message, systemImage: systemImage)
        self.currentToast = toast

        dismissTask = Task { @MainActor [weak self, toastID = toast.id] in
            let nanoSeconds = UInt64(max(0.01, duration) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoSeconds)
            guard !Task.isCancelled else { return }
            guard let self, self.currentToast?.id == toastID else { return }
            self.currentToast = nil
        }
    }

    public func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        currentToast = nil
    }
}
