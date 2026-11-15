import AppKit
import Foundation
import SwiftUI
import Testing

@Suite("Dashboard Theme Style & Store Tests")
@MainActor
struct DashboardThemeStyleTests {
    @Test func testDefaultStyleIsSoftUI() {
        let defaults = UserDefaults(suiteName: "test.dashboard.theme.default")!
        defaults.removePersistentDomain(forName: "test.dashboard.theme.default")
        let store = DashboardThemeStore(userDefaults: defaults)
        #expect(store.style == .softUI)
    }

    @Test func testThemeStyleRawValuesAndTitles() {
        #expect(DashboardThemeStyle.softUI.rawValue == "softUI")
        #expect(DashboardThemeStyle.liquidGlass.rawValue == "liquidGlass")
        #expect(DashboardThemeStyle.stripeLight.rawValue == "stripeLight")

        #expect(DashboardThemeStyle.softUI.shortTitle == "Soft UI")
        #expect(DashboardThemeStyle.liquidGlass.shortTitle == "Glass")
        #expect(DashboardThemeStyle.stripeLight.shortTitle == "Stripe")
    }

    @Test func testThemeStorePersistenceFallbackAndRedundantSuppression() {
        let defaults = UserDefaults(suiteName: "test.dashboard.theme.persistence")!
        defaults.removePersistentDomain(forName: "test.dashboard.theme.persistence")
        let store = DashboardThemeStore(userDefaults: defaults)

        store.setStyle(.liquidGlass)
        #expect(store.style == .liquidGlass)
        #expect(defaults.string(forKey: DashboardThemeStore.userDefaultsKey) == "liquidGlass")

        store.setStyle(.stripeLight)
        #expect(store.style == .stripeLight)
        #expect(defaults.string(forKey: DashboardThemeStore.userDefaultsKey) == "stripeLight")

        let reloadedStore = DashboardThemeStore(userDefaults: defaults)
        #expect(reloadedStore.style == .stripeLight)

        // Fallback on invalid rawValue
        defaults.set("unknown_hallucinated_style", forKey: DashboardThemeStore.userDefaultsKey)
        let fallbackStore = DashboardThemeStore(userDefaults: defaults)
        #expect(fallbackStore.style == .softUI)

        // Redundant setStyle suppression
        var notificationCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: DashboardThemeStore.themeDidChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            notificationCount += 1
        }
        fallbackStore.setStyle(.softUI) // Same style -> no notification
        #expect(notificationCount == 0)
        NotificationCenter.default.removeObserver(observer)
    }

    @Test func testThemeCornerRadiusDifferentiation() {
        defer { DashboardThemeStore.shared.setStyle(.softUI) }

        DashboardThemeStore.shared.setStyle(.softUI)
        #expect(DashboardTheme.cardCornerRadius == 16.0)

        DashboardThemeStore.shared.setStyle(.liquidGlass)
        #expect(DashboardTheme.cardCornerRadius == 12.0)

        DashboardThemeStore.shared.setStyle(.stripeLight)
        #expect(DashboardTheme.cardCornerRadius == 6.0)

        DashboardThemeStore.shared.setStyle(.softUI)
        #expect(DashboardTheme.cardCornerRadius == 16.0)
    }

    @Test func testThemeCanvasAndSidebarDifferentiation() {
        defer { DashboardThemeStore.shared.setStyle(.softUI) }

        DashboardThemeStore.shared.setStyle(.softUI)
        #expect(DashboardTheme.canvasBackground == Color(red: 234/255, green: 239/255, blue: 245/255))
        #expect(DashboardTheme.sidebarBackground == Color(red: 226/255, green: 232/255, blue: 240/255))

        DashboardThemeStore.shared.setStyle(.liquidGlass)
        #expect(DashboardTheme.canvasBackground == Color.clear)
        #expect(DashboardTheme.sidebarBackground == Color.white.opacity(0.20))

        DashboardThemeStore.shared.setStyle(.stripeLight)
        #expect(DashboardTheme.canvasBackground == Color(red: 244/255, green: 246/255, blue: 249/255))
        #expect(DashboardTheme.sidebarBackground == Color.white)
        #expect(DashboardTheme.hairlineBorder == Color(red: 203/255, green: 213/255, blue: 225/255))
    }

    @Test func testQuantitativeColorContrastAndAlphaMetrics() {
        defer { DashboardThemeStore.shared.setStyle(.softUI) }

        DashboardThemeStore.shared.setStyle(.softUI)
        let softCard = NSColor(DashboardTheme.cardBackground).usingColorSpace(.sRGB)!
        let softCanvas = NSColor(DashboardTheme.canvasBackground).usingColorSpace(.sRGB)!
        let diffRed = softCard.redComponent - softCanvas.redComponent
        #expect(diffRed >= 0.075)

        DashboardThemeStore.shared.setStyle(.liquidGlass)
        let glassCanvasAlpha = NSColor(DashboardTheme.canvasBackground).alphaComponent
        #expect(glassCanvasAlpha == 0.0)
        let glassCardAlpha = NSColor(DashboardTheme.cardBackground).alphaComponent
        #expect(glassCardAlpha <= 0.50)
        let glassBorderAlpha = NSColor(DashboardTheme.hairlineBorder).alphaComponent
        #expect(glassBorderAlpha >= 0.60)
    }
}
