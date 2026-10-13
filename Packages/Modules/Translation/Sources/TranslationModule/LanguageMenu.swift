import AppKit
import NotchUI

/// Language pop-up menus for the tab. The menu is a window outside the notch, which would otherwise close the
/// notch when the pointer leaves for it or clicks in it, so the notch stays pinned while the menu is open.
enum LanguageMenu {
    enum Entry {
        case option(title: String, isSelected: Bool, action: () -> Void)
        case separator
    }

    /// Shows the menu at the pointer, with the selected entry under it, and returns once it closes.
    static func show(_ entries: [Entry], notch: NotchHandle) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        var selected: NSMenuItem?
        for entry in entries {
            switch entry {
            case .option(let title, let isSelected, let action):
                let item = NSMenuItem(title: title, action: #selector(MenuAction.perform(_:)), keyEquivalent: "")
                item.target = MenuAction.target
                item.representedObject = MenuAction(action)
                item.state = isSelected ? .on : .off
                if isSelected { selected = item }
                menu.addItem(item)
            case .separator:
                menu.addItem(.separator())
            }
        }
        notch.setPinned(true)
        menu.popUp(positioning: selected, at: NSEvent.mouseLocation, in: nil)
        notch.setPinned(false)
    }
}

/// Runs a menu item's closure. Items keep the closure; the target is shared because items hold it weakly.
private final class MenuAction: NSObject {
    static let target = MenuAction {}
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func perform(_ item: NSMenuItem) {
        (item.representedObject as? MenuAction)?.action()
    }
}
