import Foundation

public final class MockNativeNotificationPoster: NativeNotificationPosting, @unchecked Sendable {
    private let lock = NSLock()
    private var _postedNotifications: [NativeNotificationPayload] = []
    private var _requestAuthorizationCallsCount = 0

    public var shouldGrantAuthorization: Bool = true

    public var postedNotifications: [NativeNotificationPayload] {
        lock.lock()
        defer { lock.unlock() }
        return _postedNotifications
    }

    public var requestAuthorizationCallsCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _requestAuthorizationCallsCount
    }

    public init() {}

    private func performRequestAuthorization() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        _requestAuthorizationCallsCount += 1
        return shouldGrantAuthorization
    }

    private func performPost(_ payload: NativeNotificationPayload) {
        lock.lock()
        defer { lock.unlock() }
        _postedNotifications.append(payload)
    }

    public func requestAuthorization() async throws -> Bool {
        performRequestAuthorization()
    }

    public func post(_ payload: NativeNotificationPayload) async throws {
        performPost(payload)
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _postedNotifications.removeAll()
        _requestAuthorizationCallsCount = 0
    }
}
