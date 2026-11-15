import Combine
import Foundation
import SwiftUI

/// Available UI themes for the MyNotch Dashboard, mirroring `DASHBOARD_STYLES_DEMO.html`.
public enum DashboardThemeStyle: String, CaseIterable, Identifiable, Sendable {
    case softUI = "softUI"
    case liquidGlass = "liquidGlass"
    case stripeLight = "stripeLight"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .softUI: return "Soft UI"
        case .liquidGlass: return "Liquid Glass"
        case .stripeLight: return "Stripe Light"
        }
    }

    public var shortTitle: String {
        switch self {
        case .softUI: return "Soft UI"
        case .liquidGlass: return "Glass"
        case .stripeLight: return "Stripe"
        }
    }

    public var systemImage: String {
        switch self {
        case .softUI: return "square.2.layers.3d"
        case .liquidGlass: return "cube.transparent"
        case .stripeLight: return "chart.bar.doc.horizontal"
        }
    }

    public var description: String {
        switch self {
        case .softUI: return "Scandinavian Soft UI (Slate 150 ấm #eaeff5, Thẻ trắng bo góc 16px, shadow bồng bềnh)"
        case .liquidGlass: return "macOS Liquid Glass (Kính mờ xuyên thấu desktop, bắt sáng specular, góc 12px)"
        case .stripeLight: return "Stripe & Mercury (Precision Fintech, viền hairline #cbd5e1, góc 6px, accent 3px)"
        }
    }
}

/// Reactive manager and persistence store for Dashboard theme styles.
@MainActor
public final class DashboardThemeStore: ObservableObject {
    public static let shared = DashboardThemeStore()
    public static let userDefaultsKey = "io.lucasvu.mynotch.dashboardThemeStyle"
    public static let themeDidChangeNotification = Notification.Name("io.lucasvu.mynotch.dashboardThemeDidChange")

    private let userDefaults: UserDefaults

    @Published public var style: DashboardThemeStyle {
        didSet {
            userDefaults.set(style.rawValue, forKey: Self.userDefaultsKey)
            NotificationCenter.default.post(name: Self.themeDidChangeNotification, object: style)
        }
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        // Chốt giữ cố định .softUI theo chỉ đạo người dùng (Scandinavian Soft UI) và Execution Contract
        self.style = .softUI
        userDefaults.set(DashboardThemeStyle.softUI.rawValue, forKey: Self.userDefaultsKey)
    }

    public func setStyle(_ newStyle: DashboardThemeStyle) {
        guard style != newStyle else { return }
        style = newStyle
    }
}
