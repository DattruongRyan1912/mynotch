import CoreGraphics
import MyNotchCore

nonisolated public enum DisplayMode: String, Codable, Sendable, CaseIterable {
    case all, main, cursor
}

/// Global interface settings (`interface.*`).
public enum InterfaceSettings {
    public static let displayMode = SettingKey("interface.displayMode", default: DisplayMode.all)
    public static let virtualNotchWidth = SettingKey("interface.virtualNotchWidth", default: 185.0, clampedTo: 120...300)
    /// When true the virtual notch is as tall as the menu bar; otherwise `virtualNotchHeight` is used.
    public static let virtualNotchMatchesMenuBar = SettingKey("interface.virtualNotchMatchesMenuBar", default: true)
    public static let virtualNotchHeight = SettingKey("interface.virtualNotchHeight", default: 32.0, clampedTo: 24...40)
    public static let openWidth = SettingKey("interface.openWidth", default: 600.0, clampedTo: 480...720)
    public static let openDelayMs = SettingKey("interface.openDelayMs", default: 150, clampedTo: 0...1000)
    public static let closeDelayMs = SettingKey("interface.closeDelayMs", default: 300, clampedTo: 0...1000)
    public static let hideInFullscreen = SettingKey("interface.hideInFullscreen", default: true)
    /// Whether the notch's windows stay out of screen recordings and shared screens.
    public static let hideFromCapture = SettingKey("interface.hideFromCapture", default: CaptureHiding.never)
}

/// Geometry inputs read from settings.
nonisolated public struct NotchLayoutConfig: Equatable, Sendable {
    public var virtualNotchWidth: CGFloat = 185
    /// nil = menu bar height.
    public var virtualNotchHeight: CGFloat?
    public var compactSideWidth: CGFloat = 64
    public var openWidth: CGFloat = 600

    public init(virtualNotchWidth: CGFloat = 185, virtualNotchHeight: CGFloat? = nil, compactSideWidth: CGFloat = 64, openWidth: CGFloat = 600) {
        self.virtualNotchWidth = virtualNotchWidth
        self.virtualNotchHeight = virtualNotchHeight
        self.compactSideWidth = compactSideWidth
        self.openWidth = openWidth
    }
}

extension NotchLayoutConfig {
    public init(settings: SettingsStore) {
        self.init(
            virtualNotchWidth: settings.value(InterfaceSettings.virtualNotchWidth),
            virtualNotchHeight: settings.value(InterfaceSettings.virtualNotchMatchesMenuBar)
                ? nil : settings.value(InterfaceSettings.virtualNotchHeight),
            openWidth: settings.value(InterfaceSettings.openWidth)
        )
    }
}
