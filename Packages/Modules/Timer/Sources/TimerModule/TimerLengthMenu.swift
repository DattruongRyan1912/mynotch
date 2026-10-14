import AppKit
import NotchUI

/// The pop-up of longer lengths. A menu is a window outside the notch, which would close the notch when the pointer
/// leaves for it or clicks in it, so the notch stays pinned while the menu is open (as the language menu of Translation
/// does). A pick starts its timer at once; the live activity then shows it even if the notch closes behind the pointer.
enum TimerLengthMenu {
    /// Shows the menu at the pointer and returns once it closes.
    static func show(_ lengths: [TimerLength], notch: NotchHandle, pick: @escaping (TimerLength) -> Void) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for length in lengths {
            let item = NSMenuItem(title: length.title, action: #selector(MenuPick.perform(_:)), keyEquivalent: "")
            item.target = MenuPick.target
            item.representedObject = MenuPick { pick(length) }
            menu.addItem(item)
        }
        notch.setPinned(true)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        notch.setPinned(false)
    }
}

/// Runs a menu item's closure. Items keep the closure; the target is shared because items hold it weakly.
private final class MenuPick: NSObject {
    static let target = MenuPick {}
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc func perform(_ item: NSMenuItem) {
        (item.representedObject as? MenuPick)?.action()
    }
}
