import AppKit
import UniformTypeIdentifiers

/// The app behind a bundle ID, as the user knows it from the Dock.
struct PlayerApp {
    var name: String
    var icon: NSImage

    /// A running app first (its localized name), then an installed one; nil when the app is not on this Mac.
    static func installed(bundleIdentifier: String) -> PlayerApp? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
           let name = running.localizedName {
            return PlayerApp(name: name, icon: running.icon ?? NSWorkspace.shared.icon(for: .application))
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path(percentEncoded: false))
        return PlayerApp(
            name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name,
            icon: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        )
    }
}
