import Foundation

/// Discovers installed applications to guard against wiping sibling app residuals (NC-MYN-025).
nonisolated public enum InstalledAppIndex {
    /// Default directories where user and system applications reside.
    public static func defaultApplicationRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        return [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            home.appending(path: "Applications"),
        ]
    }

    /// Scans installed applications up to 2 directories deep and indexes their bundle identifiers.
    public static func scan(
        roots: [URL]? = nil,
        excludingAppURL: URL? = nil
    ) -> Set<String> {
        let searchRoots = roots ?? defaultApplicationRoots()
        var bundleIDs: Set<String> = []
        let fileManager = FileManager.default
        let excludedCanonical = excludingAppURL?.resolvingSymlinksInPath().path

        for root in searchRoots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            ) else { continue }

            while let itemURL = enumerator.nextObject() as? URL {
                if enumerator.level > 2 {
                    enumerator.skipDescendants()
                    continue
                }

                if itemURL.pathExtension.lowercased() == "app" {
                    enumerator.skipDescendants()
                    if let excludedCanonical = excludedCanonical,
                       itemURL.resolvingSymlinksInPath().path == excludedCanonical {
                        continue
                    }

                    let infoPlistURL = itemURL.appending(path: "Contents/Info.plist")
                    if let data = try? Data(contentsOf: infoPlistURL),
                       let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                       let bundleID = plist["CFBundleIdentifier"] as? String, !bundleID.isEmpty {
                        bundleIDs.insert(bundleID)
                    }
                }
            }
        }

        return bundleIDs
    }
}
