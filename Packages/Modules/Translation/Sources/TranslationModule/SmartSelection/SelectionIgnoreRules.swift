import Foundation

/// What is never worth reading or showing: MyNotch's own windows, apps the user ruled out and password managers, nothing
/// selected, too much selected, and a selection already handled. Password fields are refused by the Accessibility read
/// itself, at the element it is about to read.
nonisolated enum SelectionIgnoreRules {
    /// A selection is a few words; a whole document selected by ⌘A is not worth a translation or a read.
    static let maxLength = 2_000

    /// Apps that show secrets, never read whatever the user's list says.
    static let passwordManagers: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword-osx", "com.bitwarden.desktop",
        "com.apple.keychainaccess", "com.apple.passwords", "org.keepassxc.keepassxc",
    ]

    enum Reason: Equatable, Sendable {
        case ownApplication
        case deniedApplication
        case empty
        case tooLong
        /// The same selection as the last one handled: nothing new to show, or already shown.
        case unchanged
    }

    /// Checked before anything is read from the app.
    static func application(_ application: FocusedApplication, ownProcessID: pid_t, denyList: [String]) -> Reason? {
        if application.processID == ownProcessID { return .ownApplication }
        guard let bundleID = application.bundleID?.lowercased() else { return nil }
        if passwordManagers.contains(bundleID) || denyList.contains(where: { $0.lowercased() == bundleID }) { return .deniedApplication }
        return nil
    }

    /// From the length of the selected range, which an app can give without the text, so a huge selection is never fetched.
    static func length(_ length: Int?) -> Reason? {
        guard let length else { return nil }
        if length <= 0 { return .empty }
        return length > maxLength ? .tooLong : nil
    }

    static func text(_ selection: SelectionSource, lastHandled: SelectionSource?) -> Reason? {
        let text = selection.text
        if text.allSatisfy(\.isWhitespace) { return .empty }
        // Four bytes a character at most: a text this long is too long without counting its characters.
        if text.utf8.count > maxLength * 4 || text.count > maxLength { return .tooLong }
        return selection == lastHandled ? .unchanged : nil
    }
}
