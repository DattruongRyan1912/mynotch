import Foundation
import Observation
import SwiftUI

/// Các trang cài đặt trong cửa sổ Cài đặt của MyNotch.
public enum SettingsPage: Hashable, Sendable {
    case permissions
    case general
    case interface
    case storage
    case tabs
    case module(ModuleID)
    case about
}

/// Quản lý trạng thái điều hướng và lịch sử tiến/lùi (Forward / Backward history) trong Cài đặt.
@Observable
public final class SettingsNavigation: @unchecked Sendable {
    public var selection: SettingsPage? = .general {
        didSet {
            guard let selection, selection != currentHistoryPage else { return }
            recordHistory(selection)
        }
    }

    /// Trạng thái hiển thị thực tế của cửa sổ Cài đặt (Window Visibility).
    public var isWindowVisible: Bool = false

    public private(set) var history: [SettingsPage] = [.general]
    public private(set) var historyIndex: Int = 0

    public var canGoBack: Bool { historyIndex > 0 }
    public var canGoForward: Bool { historyIndex >= 0 && historyIndex < history.count - 1 }

    private var currentHistoryPage: SettingsPage? {
        guard historyIndex >= 0, historyIndex < history.count else { return nil }
        return history[historyIndex]
    }

    public init(selection: SettingsPage? = .general) {
        self.selection = selection
        if let selection {
            self.history = [selection]
            self.historyIndex = 0
        } else {
            self.history = []
            self.historyIndex = -1
        }
    }

    public func select(_ page: SettingsPage) {
        if selection == page { return }
        selection = page
    }

    public func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        selection = history[historyIndex]
    }

    public func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        selection = history[historyIndex]
    }

    private func recordHistory(_ page: SettingsPage) {
        if historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }
        history.append(page)
        historyIndex = history.count - 1
    }
}

/// Màu sắc và biểu tượng nhận diện trang theo phong cách Apple System Settings.
public struct AppleSettingsVisuals: Sendable, Equatable {
    public let color: Color
    public let systemImage: String

    public init(color: Color, systemImage: String) {
        self.color = color
        self.systemImage = systemImage
    }

    public static func forPage(_ page: SettingsPage, modules: [any FeatureModule] = []) -> AppleSettingsVisuals {
        switch page {
        case .permissions:
            return AppleSettingsVisuals(color: .blue, systemImage: "hand.raised.fill")
        case .general:
            return AppleSettingsVisuals(color: .gray, systemImage: "gearshape.fill")
        case .interface:
            return AppleSettingsVisuals(color: .indigo, systemImage: "rectangle.topthird.inset.filled")
        case .storage:
            return AppleSettingsVisuals(color: .cyan, systemImage: "internaldrive.fill")
        case .tabs:
            return AppleSettingsVisuals(color: .orange, systemImage: "rectangle.3.group.fill")
        case .about:
            return AppleSettingsVisuals(color: .gray, systemImage: "info.circle.fill")
        case .module(let id):
            return forModule(id, fallbackImage: modules.first { $0.descriptor.id == id }?.descriptor.systemImage)
        }
    }

    public static func forModule(_ id: ModuleID, fallbackImage: String? = nil) -> AppleSettingsVisuals {
        switch id {
        case "battery":
            return AppleSettingsVisuals(color: .green, systemImage: "battery.100percent.bolt")
        case "media":
            return AppleSettingsVisuals(color: .pink, systemImage: "play.fill")
        case "equalizer":
            return AppleSettingsVisuals(color: .red, systemImage: "speaker.wave.3.fill")
        case "clipboard":
            return AppleSettingsVisuals(color: .blue, systemImage: "doc.on.clipboard.fill")
        case "screenshot":
            return AppleSettingsVisuals(color: .teal, systemImage: "camera.fill")
        case "translation":
            return AppleSettingsVisuals(color: .cyan, systemImage: "character.bubble.fill")
        case "aiagents":
            return AppleSettingsVisuals(color: .purple, systemImage: "terminal")
        case "calendar":
            return AppleSettingsVisuals(color: .red, systemImage: "calendar")
        case "todo":
            return AppleSettingsVisuals(color: .blue, systemImage: "checklist")
        case "habit":
            return AppleSettingsVisuals(color: .orange, systemImage: "arrow.triangle.2.circlepath")
        case "timer":
            return AppleSettingsVisuals(color: .orange, systemImage: "timer")
        case "shortcuts":
            return AppleSettingsVisuals(color: .indigo, systemImage: "square.stack.3d.up.fill")
        case "shelf":
            return AppleSettingsVisuals(color: .mint, systemImage: "tray.and.arrow.down.fill")
        case "performance":
            return AppleSettingsVisuals(color: .blue, systemImage: "gauge.with.dots.needle.67percent")
        case "system":
            return AppleSettingsVisuals(color: .gray, systemImage: "slider.horizontal.3")
        case "ports":
            return AppleSettingsVisuals(color: .teal, systemImage: "network")
        case "lockscreen":
            return AppleSettingsVisuals(color: Color(white: 0.35), systemImage: "lock.fill")
        case "windows":
            return AppleSettingsVisuals(color: .indigo, systemImage: "rectangle.split.2x1.fill")
        case "pet":
            return AppleSettingsVisuals(color: .orange, systemImage: "pawprint.fill")
        default:
            return AppleSettingsVisuals(color: .blue, systemImage: fallbackImage ?? "gearshape.fill")
        }
    }
}
