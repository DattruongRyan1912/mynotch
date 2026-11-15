import AppKit

/// Main menu. It shows in the menu bar only while Settings or a module's own window is open (the app is then `.regular`);
/// its key equivalents make ⌘, ⌘Q, ⌘W, ⌘M and the standard editing shortcuts work in those windows.
enum MainMenu {
    static func make(
        settingsTarget: AnyObject, settingsAction: Selector,
        dashboardTarget: AnyObject? = nil, dashboardAction: Selector? = nil
    ) -> NSMenu {
        let main = NSMenu()

        let app = NSMenu(title: "MyNotch")
        if let dashboardTarget, let dashboardAction {
            let dashItem = app.addItem(withTitle: "Bảng điều khiển…", action: dashboardAction, keyEquivalent: "b")
            dashItem.keyEquivalentModifierMask = [.control, .option]
            dashItem.target = dashboardTarget
        }
        app.addItem(withTitle: "Settings…", action: settingsAction, keyEquivalent: ",").target = settingsTarget
        app.addItem(.separator())
        app.addItem(withTitle: "Quit MyNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addSubmenu(app)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z").keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addSubmenu(edit)

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addSubmenu(window)
        return main
    }
}

private extension NSMenu {
    func addSubmenu(_ submenu: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}
