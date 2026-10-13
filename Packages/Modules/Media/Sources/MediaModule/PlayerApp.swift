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

/// Remembers each bundle ID's app, including "not installed", for as long as a view keeps it: LaunchServices
/// lookups are too slow to repeat on every redraw of a list.
final class PlayerAppCache {
    private let lookUp: @MainActor (String) -> PlayerApp?
    private var apps: [String: PlayerApp?] = [:]

    init(lookUp: @escaping @MainActor (String) -> PlayerApp? = PlayerApp.installed) {
        self.lookUp = lookUp
    }

    func app(for bundleID: String) -> PlayerApp? {
        if let cached = apps[bundleID] { return cached }
        let app = lookUp(bundleID)
        apps[bundleID] = .some(app)
        return app
    }
}
