import AppKit
import Foundation
import SwiftUI

@main
struct ThemeTestRunner {
    @MainActor
    static func main() {
        print("==================================================")
        print("🧪 Running DashboardThemeStyleTests (Swift 6.0)...")
        print("==================================================")

        let testDefaults = UserDefaults(suiteName: "test.dashboard.theme.unified")!
        testDefaults.removePersistentDomain(forName: "test.dashboard.theme.unified")
        let store = DashboardThemeStore(userDefaults: testDefaults)

        // 1. Default style is softUI
        assert(store.style == .softUI, "Default style must be softUI")
        print("✅ testDefaultStyleIsSoftUI passed")

        // 2. Raw values and titles
        assert(DashboardThemeStyle.softUI.rawValue == "softUI")
        assert(DashboardThemeStyle.liquidGlass.rawValue == "liquidGlass")
        assert(DashboardThemeStyle.stripeLight.rawValue == "stripeLight")

        assert(DashboardThemeStyle.softUI.shortTitle == "Soft UI")
        assert(DashboardThemeStyle.liquidGlass.shortTitle == "Glass")
        assert(DashboardThemeStyle.stripeLight.shortTitle == "Stripe")
        print("✅ testThemeStyleRawValuesAndTitles passed")

        // 3. Persistence, Fallback & Redundant Notification Suppression
        store.setStyle(.liquidGlass)
        assert(store.style == .liquidGlass)
        assert(testDefaults.string(forKey: DashboardThemeStore.userDefaultsKey) == "liquidGlass")

        store.setStyle(.stripeLight)
        assert(store.style == .stripeLight)
        assert(testDefaults.string(forKey: DashboardThemeStore.userDefaultsKey) == "stripeLight")

        let reloaded = DashboardThemeStore(userDefaults: testDefaults)
        assert(reloaded.style == .stripeLight)

        // Fallback on unknown string
        testDefaults.set("unknown_hallucinated_style", forKey: DashboardThemeStore.userDefaultsKey)
        let fallbackStore = DashboardThemeStore(userDefaults: testDefaults)
        assert(fallbackStore.style == .softUI, "Unknown style in defaults must fallback to .softUI")

        // Redundant setStyle suppression
        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: DashboardThemeStore.themeDidChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        fallbackStore.setStyle(.softUI) // Already .softUI
        assert(notificationCount == 0, "Redundant setStyle must NOT post notification")
        NotificationCenter.default.removeObserver(observer)
        print("✅ testThemeStorePersistenceFallbackAndRedundantSuppression passed")

        // 4. Geometry & Corner Radius Differentiation (16 / 12 / 6)
        DashboardThemeStore.shared.setStyle(.softUI)
        assert(DashboardTheme.cardCornerRadius == 16.0, "Soft UI corner radius must be 16.0")

        DashboardThemeStore.shared.setStyle(.liquidGlass)
        assert(DashboardTheme.cardCornerRadius == 12.0, "Liquid Glass corner radius must be 12.0")

        DashboardThemeStore.shared.setStyle(.stripeLight)
        assert(DashboardTheme.cardCornerRadius == 6.0, "Stripe Light corner radius must be 6.0")

        DashboardThemeStore.shared.setStyle(.softUI)
        assert(DashboardTheme.cardCornerRadius == 16.0, "Soft UI restored corner radius must be 16.0")
        print("✅ testThemeCornerRadiusDifferentiation passed")

        // 5. Canvas & Sidebar Background Differentiation
        DashboardThemeStore.shared.setStyle(.softUI)
        assert(DashboardTheme.canvasBackground == Color(red: 234/255, green: 239/255, blue: 245/255), "Soft UI canvas must be #eaeff5")
        assert(DashboardTheme.sidebarBackground == Color(red: 226/255, green: 232/255, blue: 240/255), "Soft UI sidebar must be #e2e8f0")

        DashboardThemeStore.shared.setStyle(.liquidGlass)
        assert(DashboardTheme.canvasBackground == Color.clear, "Liquid Glass canvas must be Color.clear")
        assert(DashboardTheme.sidebarBackground == Color.white.opacity(0.20), "Liquid Glass sidebar must be white.opacity(0.20)")

        DashboardThemeStore.shared.setStyle(.stripeLight)
        assert(DashboardTheme.canvasBackground == Color(red: 244/255, green: 246/255, blue: 249/255), "Stripe Light canvas must be #f4f6f9")
        assert(DashboardTheme.sidebarBackground == Color.white, "Stripe Light sidebar must be Color.white")
        print("✅ testThemeCanvasAndSidebarDifferentiation passed")

        // 6. Quantitative Color Contrast & Alpha Metrics via NSColor
        DashboardThemeStore.shared.setStyle(.softUI)
        let softCard = NSColor(DashboardTheme.cardBackground).usingColorSpace(.sRGB)!
        let softCanvas = NSColor(DashboardTheme.canvasBackground).usingColorSpace(.sRGB)!
        let diffRed = softCard.redComponent - softCanvas.redComponent
        assert(diffRed >= 0.075, "Soft UI card vs canvas red contrast must be >= 0.075, got \(diffRed)")

        DashboardThemeStore.shared.setStyle(.liquidGlass)
        let glassCanvasAlpha = NSColor(DashboardTheme.canvasBackground).alphaComponent
        assert(glassCanvasAlpha == 0.0, "Liquid Glass canvas alpha must be 0.0, got \(glassCanvasAlpha)")
        let glassCardAlpha = NSColor(DashboardTheme.cardBackground).alphaComponent
        assert(glassCardAlpha <= 0.50, "Liquid Glass card alpha must be <= 0.50, got \(glassCardAlpha)")
        let glassBorderAlpha = NSColor(DashboardTheme.hairlineBorder).alphaComponent
        assert(glassBorderAlpha >= 0.60, "Liquid Glass hairline border alpha must be >= 0.60, got \(glassBorderAlpha)")

        DashboardThemeStore.shared.setStyle(.stripeLight)
        let stripeBorder = DashboardTheme.hairlineBorder
        assert(stripeBorder == Color(red: 203/255, green: 213/255, blue: 225/255), "Stripe border must be #cbd5e1")
        print("✅ testQuantitativeColorContrastAndAlphaMetrics passed")

        // 7. Cleanup & restore default style
        DashboardThemeStore.shared.setStyle(.softUI)

        print("==================================================")
        print("🎉 ALL MANDATORY THEME TESTS PASSED (0 failures)!")
        print("==================================================")
    }
}
