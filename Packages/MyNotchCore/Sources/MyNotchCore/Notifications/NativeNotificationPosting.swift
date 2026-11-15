import Foundation

public struct NativeNotificationPayload: Sendable, Equatable {
    public let id: String
    public let title: String
    public let body: String
    public let subtitle: String?
    public let sound: Bool

    public init(
        id: String = UUID().uuidString,
        title: String,
        body: String,
        subtitle: String? = nil,
        sound: Bool = true
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.subtitle = subtitle
        self.sound = sound
    }
}

public protocol NativeNotificationPosting: Sendable {
    func requestAuthorization() async throws -> Bool
    func post(_ payload: NativeNotificationPayload) async throws
}
