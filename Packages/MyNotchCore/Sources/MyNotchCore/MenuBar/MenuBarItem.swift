import CoreGraphics
import Foundation

/// One status item of another app (an entry of its `AXExtrasMenuBar`), as far as the bar needs to know it. Only its title,
/// description and frame are read from the app, and none of them is ever logged.
nonisolated public struct MenuBarItem: Equatable, Sendable, Identifiable {
    /// Stable between two looks as long as the app's items keep their order: the owner and the position in its extras bar.
    public let id: String
    public let pid: Int32
    public let ownerBundleID: String?
    public let ownerName: String
    public let title: String?
    public let details: String?
    /// Where the item's window is, in AppKit screen coordinates (`MenuBarCoordinates`).
    public let frame: CGRect
    /// Where the source listed it, which orders items whose frames say nothing.
    public let order: Int

    public init(
        id: String, pid: Int32, ownerBundleID: String?, ownerName: String, title: String?, details: String?, frame: CGRect, order: Int
    ) {
        self.id = id
        self.pid = pid
        self.ownerBundleID = ownerBundleID
        self.ownerName = ownerName
        self.title = title
        self.details = details
        self.frame = frame
        self.order = order
    }

    /// What the item's button says when the pointer rests on it: the app, and the item's own title or description when it has
    /// one that says more.
    public var toolTip: String {
        let own = [title, details].lazy.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        guard let own, own != ownerName else { return ownerName }
        return "\(ownerName): \(own)"
    }
}

/// Whose items the bar lists.
nonisolated public enum MenuBarItemOwners {
    /// Not MyNotch's own, and not Apple's: Control Center and the system UI server keep a placeholder for every module the user has
    /// switched off, which are not items anyone could open. The bundle ID is compared with its trailing dot, so an app whose ID merely
    /// starts with "com.apple" stays in.
    public static func isListed(bundleID: String?, pid: Int32, ownPID: Int32) -> Bool {
        guard pid != ownPID else { return false }
        return !(bundleID?.hasPrefix("com.apple.") ?? false)
    }
}

/// What can be done to an item through Accessibility.
nonisolated public enum MenuBarItemAction: Equatable, Hashable, Sendable {
    /// Presses the item as a click does: opens its menu, or runs what the app does on a click.
    case press
    /// Opens the item's menu, which is what a right-click does.
    case showMenu
}

nonisolated public enum MenuBarItemActionResult: Equatable, Sendable {
    /// The app took it. A call that timed out counts too: an app whose menu is open does not answer until it closes.
    case performed
    /// The item does not have that action, so another one may do.
    case unsupported
    case failed
}

/// The apps' status items through Accessibility. The real one is the app's; tests use a fake.
public protocol MenuBarItemSource: AnyObject {
    /// Whether the app may use Accessibility. Without it nothing can be listed or pressed.
    var isTrusted: Bool { get }
    /// Every status item of every running app whose owner is listed, in AppKit coordinates. Reading takes a moment (each app is
    /// asked), so it is done off the main thread.
    func items() async -> [MenuBarItem]
    /// Where the item's window is right now; nil when it is gone.
    func currentFrame(of id: String) -> CGRect?
    func perform(_ action: MenuBarItemAction, on id: String) -> MenuBarItemActionResult
}

/// The hider's sections, which the fallback shows for a moment to reach an item the separators push away.
public protocol MenuBarSectionControl: AnyObject {
    var level: MenuBarHider.Level { get }
    /// The apps the system keeps off the menu bar now, with their sections; nil when nothing hides that way
    /// (`MenuBarNativeHiding`), and the separators' places say what is hidden.
    var hiddenApps: [String: MenuBarSection]? { get }
    func revealAll()
    @discardableResult func restore(to level: MenuBarHider.Level) -> Bool
}
