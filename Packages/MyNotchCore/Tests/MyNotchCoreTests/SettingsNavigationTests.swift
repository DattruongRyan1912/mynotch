import Foundation
import Testing
@testable import MyNotchCore

@Suite
struct SettingsNavigationTests {

    // Test Case 1 (Happy Path): Kiểm tra khởi tạo và luồng duyệt tiến/lùi lịch sử
    @Test
    func testNavigationHistoryAndForwardBackFlow() {
        let nav = SettingsNavigation()
        #expect(nav.selection == .general)
        #expect(nav.canGoBack == false)
        #expect(nav.canGoForward == false)

        nav.select(.interface)
        #expect(nav.selection == .interface)
        #expect(nav.canGoBack == true)
        #expect(nav.canGoForward == false)

        nav.select(.storage)
        #expect(nav.selection == .storage)
        #expect(nav.canGoBack == true)

        nav.goBack()
        #expect(nav.selection == .interface)
        #expect(nav.canGoBack == true)
        #expect(nav.canGoForward == true)

        nav.goForward()
        #expect(nav.selection == .storage)
        #expect(nav.canGoBack == true)
        #expect(nav.canGoForward == false)
    }

    // Test Case 2 (Edge Case 1): Chọn lại chính trang hiện tại không được làm phình lịch sử
    @Test
    func testSelectingSamePageDoesNotDuplicateHistory() {
        let nav = SettingsNavigation()
        #expect(nav.history.count == 1)

        nav.select(.general)
        #expect(nav.history.count == 1)
        #expect(nav.canGoBack == false)
    }

    // Test Case 3 (Edge Case 2): Phân nhánh lịch sử phải cắt bỏ forward stack
    @Test
    func testBranchingHistoryTruncatesForwardStack() {
        let nav = SettingsNavigation()
        nav.select(.interface)
        nav.select(.storage)
        nav.goBack() // Đang ở .interface, phía trước là .storage
        #expect(nav.canGoForward == true)

        // Phân nhánh mới sang .permissions -> .storage phải bị loại bỏ
        nav.select(.permissions)
        #expect(nav.selection == .permissions)
        #expect(nav.canGoForward == false)
        #expect(nav.history == [.general, .interface, .permissions])
    }

    // Test Case 4 (Visual Mapping & Fallback Boundaries):
    @Test
    func testAppleSettingsVisualsMappingAndFallbacks() {
        let permVisual = AppleSettingsVisuals.forPage(.permissions)
        #expect(permVisual.systemImage == "hand.raised.fill")

        let generalVisual = AppleSettingsVisuals.forPage(.general)
        #expect(generalVisual.systemImage == "gearshape.fill")

        let clipVisual = AppleSettingsVisuals.forModule("clipboard")
        #expect(clipVisual.systemImage == "doc.on.clipboard.fill")

        // Fallback khi gặp module ID lạ (Lowercase ASCII conformant per NC-MYN-025)
        let unknownVisual = AppleSettingsVisuals.forModule("customunknown", fallbackImage: "star.fill")
        #expect(unknownVisual.systemImage == "star.fill")
    }
}
