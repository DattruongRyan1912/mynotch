import Foundation

/// Enforces path safety boundaries for uninstallation and system clean operations (NC-MYN-025, 027, 028).
nonisolated public enum CleanerPathGuard {
    public enum Verdict: Equatable, Sendable {
        case allowed
        case rejected(String)
    }

    /// Verifies if a given path is legally cleanable:
    /// (a) within the user's home directory (e.g., ~/Library residuals or ~/Applications), or
    /// (b) an .app bundle directly inside /Applications or /Applications/Utilities.
    public static func check(_ url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Verdict {
        let canonicalHome = home.resolvingSymlinksInPath().standardized.path
        let canonicalTarget = url.resolvingSymlinksInPath().standardized.path

        // Rejection: Directory traversal attempts
        if url.pathComponents.contains("..") {
            return .rejected("Path contains relative traversal elements ('..')")
        }

        let inHome = canonicalTarget.hasPrefix(canonicalHome + "/")
        let inApplications = isApplicationBundle(canonicalTarget)

        // Must strictly reside inside home or be an application bundle in /Applications
        guard inHome || inApplications else {
            return .rejected("Path is outside permitted cleanup roots: \(canonicalTarget)")
        }

        // Never touch root or home directory itself
        if canonicalTarget == canonicalHome || canonicalTarget == "/" {
            return .rejected("Target path is user home or system root")
        }

        // Never touch ~/Library directly
        let libraryPath = (canonicalHome as NSString).appendingPathComponent("Library")
        if canonicalTarget == libraryPath {
            return .rejected("Target path is the ~/Library root")
        }

        // Blocklist: System files
        let systemRoots = ["/System", "/usr", "/bin", "/sbin", "/private"]
        if systemRoots.contains(where: { hasPathPrefix(canonicalTarget, $0) }) {
            return .rejected("Path resides in system-protected directory")
        }

        // Blocklist: iCloud Drive and CloudStorage (NC-MYN-028)
        let mobileDocs = (libraryPath as NSString).appendingPathComponent("Mobile Documents")
        let cloudStorage = (libraryPath as NSString).appendingPathComponent("CloudStorage")
        if canonicalTarget == mobileDocs || canonicalTarget.hasPrefix(mobileDocs + "/") {
            return .rejected("Target path is within iCloud Mobile Documents (cloud sync guard)")
        }
        if canonicalTarget == cloudStorage || canonicalTarget.hasPrefix(cloudStorage + "/") {
            return .rejected("Target path is within CloudStorage directory")
        }

        // Blocklist: Apple system bundle IDs and components
        let lastComponent = url.lastPathComponent
        if lastComponent.lowercased().hasPrefix("com.apple.") {
            return .rejected("Target path belongs to Apple system identifier: \(lastComponent)")
        }

        // Blocklist: Self-destruction guard for MyNotch
        let lowerPath = canonicalTarget.lowercased()
        if lowerPath.contains("mynotch.app") || lowerPath.contains("io.lucasvu.mynotch") {
            return .rejected("Target path belongs to MyNotch application")
        }
        if lastComponent.lowercased() == "mynotch" {
            return .rejected("Target path is named MyNotch")
        }

        // Bundle Info.plist inspection for /Applications items
        if inApplications && !inHome {
            if let bundleID = Bundle(url: URL(fileURLWithPath: canonicalTarget))?.bundleIdentifier,
               isProtectedBundleID(bundleID) {
                return .rejected("Target application belongs to Apple/MyNotch bundle identifier: \(bundleID)")
            }
        }

        return .allowed
    }

    static func isProtectedBundleID(_ id: String?) -> Bool {
        guard let id = id?.trimmingCharacters(in: .whitespaces), !id.isEmpty else { return false }
        let lower = id.lowercased()
        return lower.hasPrefix("com.apple.") || lower == "io.lucasvu.mynotch"
    }

    private static func hasPathPrefix(_ path: String, _ root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }

    private static func isApplicationBundle(_ path: String) -> Bool {
        let ns = path as NSString
        guard ns.pathExtension.lowercased() == "app" else { return false }
        let parent = ns.deletingLastPathComponent
        guard parent == "/Applications" || parent == "/Applications/Utilities" else { return false }
        let name = ns.lastPathComponent
        return name != ".app" && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
