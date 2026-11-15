import Foundation
import UserNotifications

public final class SystemNativeNotificationCenter: NativeNotificationPosting, @unchecked Sendable {
    public static let shared = SystemNativeNotificationCenter()

    private var center: UNUserNotificationCenter? {
        // Guard against calling UNUserNotificationCenter.current() in CLI/test runner environments
        // which lack an app bundle and throw an uncatchable NSException.
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else {
            return nil
        }
        return UNUserNotificationCenter.current()
    }

    public init() {}

    public func requestAuthorization() async throws -> Bool {
        guard let center else { return false }
        return try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    public func post(_ payload: NativeNotificationPayload) async throws {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        if let subtitle = payload.subtitle {
            content.subtitle = subtitle
        }
        if payload.sound {
            content.sound = .default
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let request = UNNotificationRequest(identifier: payload.id, content: content, trigger: trigger)

        try await center.add(request)
    }
}
