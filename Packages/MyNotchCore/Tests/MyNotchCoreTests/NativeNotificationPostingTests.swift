import Foundation
import Testing
@testable import MyNotchCore

@Suite("Native Notification Posting Tests")
struct NativeNotificationPostingTests {
    @Test("MockNativeNotificationPoster captures payloads and manages authorization")
    func testMockPosterRecordsPayloads() async throws {
        let mock = MockNativeNotificationPoster()
        let auth = try await mock.requestAuthorization()
        #expect(auth == true)
        #expect(mock.requestAuthorizationCallsCount == 1)

        let payload = NativeNotificationPayload(
            id: "test.alert",
            title: "Tiêu đề thử nghiệm",
            body: "Nội dung thông báo",
            subtitle: "Phụ đề",
            sound: true
        )
        try await mock.post(payload)

        #expect(mock.postedNotifications.count == 1)
        #expect(mock.postedNotifications.first?.id == "test.alert")
        #expect(mock.postedNotifications.first?.title == "Tiêu đề thử nghiệm")
        #expect(mock.postedNotifications.first?.body == "Nội dung thông báo")
        #expect(mock.postedNotifications.first?.subtitle == "Phụ đề")
        #expect(mock.postedNotifications.first?.sound == true)

        mock.reset()
        #expect(mock.postedNotifications.isEmpty)
        #expect(mock.requestAuthorizationCallsCount == 0)
    }
}
