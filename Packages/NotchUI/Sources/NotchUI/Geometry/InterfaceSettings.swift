import CoreGraphics
import MyNotchCore

nonisolated public enum DisplayMode: String, Codable, Sendable, CaseIterable {
    /// A notch on every display.
    case all
    /// A notch on the display with the menu bar only.
    case main
    /// A notch on the display the user is working on, which follows the pointer (see `ActiveDisplay`). Stored as
    /// "cursor", the name this mode had before it settled, so an earlier choice keeps its meaning.
    case cursor
}

/// How the notch of a display without a hardware notch is drawn (`interface.virtualNotchStyle`).
nonisolated public enum VirtualNotchStyle: String, Codable, Sendable, CaseIterable {
    /// The notch's own outline, stuck to the top edge of the screen, as it always was. The default.
    case notch
    /// A pill that floats a few points below the top edge, like the Dynamic Island, and grows into a rounded rectangle when it opens.
    case pill
}

/// Global interface settings (`interface.*`).
public enum InterfaceSettings {
    public static let displayMode = SettingKey("interface.displayMode", default: DisplayMode.all)
    public static let virtualNotchWidth = SettingKey("interface.virtualNotchWidth", default: 185.0, clampedTo: 120...300)
    /// When true the virtual notch is as tall as the menu bar; otherwise `virtualNotchHeight` is used.
    public static let virtualNotchMatchesMenuBar = SettingKey("interface.virtualNotchMatchesMenuBar", default: true)
    public static let virtualNotchHeight = SettingKey("interface.virtualNotchHeight", default: 32.0, clampedTo: 24...40)
    /// Whether the virtual notch is stuck to the top edge or a floating pill. A display with a hardware notch never changes.
    public static let virtualNotchStyle = SettingKey("interface.virtualNotchStyle", default: VirtualNotchStyle.notch)
    /// How tall the floating pill is, which is its own: the notch style keeps its height (`virtualNotchHeight`, or the menu bar's).
    public static let pillHeight = SettingKey(
        "interface.pillHeight", default: 32.0,
        clampedTo: Double(NotchGeometry.pillHeightLimits.lowerBound)...Double(NotchGeometry.pillHeightLimits.upperBound)
    )
    public static let openWidth = SettingKey(
        "interface.openWidth", default: 600.0,
        clampedTo: Double(NotchGeometry.openWidthLimits.lowerBound)...Double(NotchGeometry.openWidthLimits.upperBound)
    )
    public static let openDelayMs = SettingKey("interface.openDelayMs", default: 150, clampedTo: 0...1000)
    public static let closeDelayMs = SettingKey("interface.closeDelayMs", default: 300, clampedTo: 0...1000)
    public static let hideInFullscreen = SettingKey("interface.hideInFullscreen", default: true)
    /// Whether the notch's windows stay out of screen recordings and shared screens.
    public static let hideFromCapture = SettingKey("interface.hideFromCapture", default: CaptureHiding.never)
    /// A two-finger sideways swipe on the open notch moves to the previous or next tab.
    public static let swipeBetweenTabs = SettingKey("interface.swipeBetweenTabs", default: true)
    /// The accent of the notch's controls: macOS's own until the user picks one.
    public static let accent = SettingKey("interface.accent", default: NotchAccent.system)
    /// A blur behind the content of the open notch, in the classic look. Never the collapsed notch there, which has to match the
    /// hardware cutout. Liquid Glass supersedes it, and the choice is kept for when the user goes back to the classic look.
    public static let glass = SettingKey("interface.glass", default: false)
    /// Whether the notch is black (as it always was) or Liquid Glass.
    public static let look = SettingKey("interface.look", default: NotchLook.classic)
    /// A hint of the accent colour in the Liquid Glass.
    public static let glassTint = SettingKey("interface.glassTint", default: false)
    /// How clear the Liquid Glass is: the balanced one, which reads on any background, or the clear one of Control Center.
    public static let glassClarity = SettingKey("interface.glassClarity", default: NotchGlassClarity.balanced)
    /// What the open notch's glass is made of: one piece, or a capsule for the tab bar and a tile for the content with the desktop
    /// showing between them.
    public static let glassShape = SettingKey("interface.glassShape", default: NotchGlassShape.slab)
    /// A two-finger swipe down over the collapsed notch opens it, and up over the open notch closes it.
    public static let swipeToOpen = SettingKey("interface.swipeToOpen", default: true)
    public static let swipeSensitivity = SettingKey("interface.swipeSensitivity", default: SwipeSensitivity.medium)
    /// A light tap on the trackpad for a gesture that opens, closes or changes something.
    public static let haptics = SettingKey("interface.haptics", default: true)
}

/// Geometry inputs read from settings.
nonisolated public struct NotchLayoutConfig: Equatable, Sendable {
    public var virtualNotchWidth: CGFloat = 185
    /// nil = menu bar height.
    public var virtualNotchHeight: CGFloat?
    public var compactSideWidth: CGFloat = 64
    public var openWidth: CGFloat = 600
    /// How a display without a hardware notch draws it; `NotchGeometry` ignores it on one that has.
    public var virtualNotchStyle: VirtualNotchStyle = .notch
    /// How tall the floating pill is; the geometry holds it to `NotchGeometry.pillHeightLimits`, and ignores it for a notch.
    public var pillHeight: CGFloat = 32
    /// Whether the open notch is made of Liquid Glass tiles (a capsule for the tab bar and a tile for the content). The tiles take room
    /// of their own around what a tab shows, so the open notch is taller by that much and a tab gets the room it gets in one piece.
    public var opensAsTiles = false

    public init(
        virtualNotchWidth: CGFloat = 185, virtualNotchHeight: CGFloat? = nil, compactSideWidth: CGFloat = 64, openWidth: CGFloat = 600,
        virtualNotchStyle: VirtualNotchStyle = .notch, opensAsTiles: Bool = false, pillHeight: CGFloat = 32
    ) {
        self.virtualNotchWidth = virtualNotchWidth
        self.virtualNotchHeight = virtualNotchHeight
        self.compactSideWidth = compactSideWidth
        self.openWidth = openWidth
        self.virtualNotchStyle = virtualNotchStyle
        self.opensAsTiles = opensAsTiles
        self.pillHeight = pillHeight
    }
}

extension NotchLayoutConfig {
    public init(settings: SettingsStore) {
        self.init(
            virtualNotchWidth: settings.value(InterfaceSettings.virtualNotchWidth),
            virtualNotchHeight: settings.value(InterfaceSettings.virtualNotchMatchesMenuBar)
                ? nil : settings.value(InterfaceSettings.virtualNotchHeight),
            openWidth: settings.value(InterfaceSettings.openWidth),
            virtualNotchStyle: settings.value(InterfaceSettings.virtualNotchStyle),
            opensAsTiles: settings.value(InterfaceSettings.look) == .liquidGlass && settings.value(InterfaceSettings.glassShape) == .tiles,
            pillHeight: settings.value(InterfaceSettings.pillHeight)
        )
    }
}
