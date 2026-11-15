import Foundation
import MyNotchCore
import MyNotchTestSupport
import Testing
@testable import NotchUI

@Suite struct DashboardThemeTests {
    @Test func testDashboardThemeStoreEnforcesSoftUIDefault() {
        let defaults = makeIsolatedDefaults()
        // Gán giá trị cũ (liquidGlass) hoặc giá trị khác vào UserDefaults
        defaults.set("liquidGlass", forKey: DashboardThemeStore.userDefaultsKey)
        #expect(defaults.string(forKey: DashboardThemeStore.userDefaultsKey) == "liquidGlass")

        // Khởi tạo DashboardThemeStore với defaults có giá trị cũ
        let store = DashboardThemeStore(userDefaults: defaults)

        // BẮT BUỘC chốt giữ và trả về .softUI theo tiêu chuẩn Scandinavian Soft UI
        #expect(store.style == .softUI)
        #expect(defaults.string(forKey: DashboardThemeStore.userDefaultsKey) == DashboardThemeStyle.softUI.rawValue)
    }

    @Test func testDashboardThemeStoreWithJunkValueEnforcesSoftUI() {
        let defaults = makeIsolatedDefaults()
        defaults.set("random_invalid_theme_xyz", forKey: DashboardThemeStore.userDefaultsKey)

        let store = DashboardThemeStore(userDefaults: defaults)
        #expect(store.style == .softUI)
    }
}
