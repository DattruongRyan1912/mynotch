import AppKit

/// App and file icons for the cards. Each lookup asks LaunchServices, so it happens once per app or file.
enum ClipboardIcons {
    /// nil values remember apps that are not installed.
    private static var appIcons: [String: NSImage?] = [:]
    private static let fileIcons = NSCache<NSString, NSImage>()

    /// nil when no app with this bundle ID is installed.
    static func app(bundleID: String) -> NSImage? {
        if let cached = appIcons[bundleID] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path(percentEncoded: false)) }
        appIcons[bundleID] = icon
        return icon
    }

    /// The Finder icon of a copied file; a generic one once the file is gone.
    static func file(_ url: URL) -> NSImage {
        let path = url.path(percentEncoded: false)
        if let cached = fileIcons.object(forKey: path as NSString) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        fileIcons.setObject(icon, forKey: path as NSString)
        return icon
    }
}
