import Foundation

/// What is never worth reading or showing: MyNotch's own windows, apps the user ruled out, nothing selected, too much
/// selected, and a selection whose chip is already up. Password fields are refused by the Accessibility client itself, at
/// the element it is about to read.
nonisolated enum SelectionIgnoreRules {
    /// A selection is a few words; a whole document selected by ⌘A is not worth a translation or a read.
    static let maxLength = 2_000

    enum Reason: Equatable, Sendable {
        case ownApplication
        case deniedApplication
        case empty
        case tooLong
        /// The chip already shows this selection.
        case unchanged
    }

    /// Checked before anything is read from the app.
    static func application(_ application: FocusedApplication, ownProcessID: pid_t, denyList: [String]) -> Reason? {
        if application.processID == ownProcessID { return .ownApplication }
        if let bundleID = application.bundleID, denyList.contains(bundleID) { return .deniedApplication }
        return nil
    }

    /// From the length of the selected range, which an app can give without the text, so a huge selection is never fetched.
    static func length(_ length: Int?) -> Reason? {
        guard let length else { return nil }
        if length <= 0 { return .empty }
        return length > maxLength ? .tooLong : nil
    }

    static func text(_ selection: SelectionSource, lastShown: SelectionSource?) -> Reason? {
        let text = selection.text
        if text.allSatisfy(\.isWhitespace) { return .empty }
        // Four bytes a character at most: a text this long is too long without counting its characters.
        if text.utf8.count > maxLength * 4 || text.count > maxLength { return .tooLong }
        return selection == lastShown ? .unchanged : nil
    }
}
