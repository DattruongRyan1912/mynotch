import Darwin
import Foundation

/// Confidence tier of a residual item (NC-MYN-025).
nonisolated public enum ResidualTier: String, CaseIterable, Equatable, Sendable {
    case tier1 = "Chính xác (Bundle ID)"
    case tier2 = "Tên ứng dụng"
    case tier3 = "Thư mục nhà phát triển"
}

/// An identified leftover file or directory on disk.
nonisolated public struct Residual: Identifiable, Equatable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let tier: ResidualTier
    public let bytes: Int64
    public let selectedByDefault: Bool
    public let locked: Bool
    public let deniedFDA: Bool
    public let note: String?

    public init(
        url: URL,
        tier: ResidualTier,
        bytes: Int64,
        selectedByDefault: Bool,
        locked: Bool = false,
        deniedFDA: Bool = false,
        note: String? = nil
    ) {
        self.url = url
        self.tier = tier
        self.bytes = bytes
        self.selectedByDefault = selectedByDefault
        self.locked = locked
        self.deniedFDA = deniedFDA
        self.note = note
    }
}

/// Scans ~/Library for application leftovers across Tier 1, Tier 2, and Tier 3 with vendor and sibling guards.
nonisolated public enum ResidualScanner {
    /// Known multi-app vendor directory names in Application Support / Caches.
    public static let knownVendors: Set<String> = ["adobe", "google", "microsoft", "jetbrains", "apple"]

    /// Performs a non-isolated residual scan inside the user's home directory.
    public static func scan(
        info: AppBundleInfo,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        installedAppIDs: Set<String>
    ) -> [Residual] {
        var residuals: [Residual] = []
        let libraryURL = home.appending(path: "Library")

        // 1. Tier 1 Root Folders in ~/Library
        let tier1Locations: [(subpath: String, isFolderDirect: Bool)] = [
            ("Preferences", false),
            ("Application Support", true),
            ("Caches", true),
            ("Containers", true),
            ("Saved Application State", false),
            ("HTTPStorages", true),
            ("WebKit", true),
        ]

        let fileManager = FileManager.default

        for (subpath, _) in tier1Locations {
            let rootURL = libraryURL.appending(path: subpath)

            // Probe directory with low-level POSIX open to detect FDA EPERM (NC-MYN-026)
            let fd = open(rootURL.path, O_RDONLY | O_DIRECTORY)
            if fd < 0 {
                let err = errno
                if err == EPERM || err == EACCES {
                    residuals.append(Residual(
                        url: rootURL,
                        tier: .tier1,
                        bytes: 0,
                        selectedByDefault: false,
                        deniedFDA: true,
                        note: "Không thể đọc \(subpath) (Cần cấp Full Disk Access)"
                    ))
                    continue
                } else if err == ENOENT {
                    continue
                }
            } else {
                close(fd)
            }

            guard let contents = try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) else {
                continue
            }

            for itemURL in contents {
                let itemName = itemURL.lastPathComponent

                // Tier 1 Matching: Exact ID or Exact ID + known extensions (.plist, .savedState) per NC-MYN-025
                let isExactID = info.ownedIDs.contains(itemName)
                    || info.ownedIDs.contains { itemName == "\($0).plist" || itemName == "\($0).savedState" }

                if isExactID {
                    // Sibling Guard: If itemName belongs to another currently installed app (e.g. Chrome.canary vs Chrome), skip!
                    let isSibling = installedAppIDs.contains { otherID in
                        !info.ownedIDs.contains(otherID) && (itemName == otherID || itemName.hasPrefix(otherID + "."))
                    }
                    if isSibling {
                        continue
                    }

                    guard case .allowed = CleanerPathGuard.check(itemURL, home: home) else {
                        continue
                    }

                    let size = AppBundleAnalyzer.calculateAllocatedSize(of: itemURL)
                    residuals.append(Residual(
                        url: itemURL,
                        tier: .tier1,
                        bytes: size,
                        selectedByDefault: true
                    ))
                }
            }
        }

        // 2. Tier 2: App Name Matching in Application Support and Caches
        let tier2Locations = ["Application Support", "Caches"]
        let candidateNames: Set<String> = [
            info.displayName.lowercased(),
            info.url.deletingPathExtension().lastPathComponent.lowercased()
        ]

        for subpath in tier2Locations {
            let rootURL = libraryURL.appending(path: subpath)
            guard let contents = try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) else {
                continue
            }

            for itemURL in contents {
                let name = itemURL.lastPathComponent.lowercased()
                // Do not re-add Tier 1 items
                if residuals.contains(where: { $0.url == itemURL }) { continue }

                if candidateNames.contains(name) {
                    guard case .allowed = CleanerPathGuard.check(itemURL, home: home) else {
                        continue
                    }

                    let size = AppBundleAnalyzer.calculateAllocatedSize(of: itemURL)
                    residuals.append(Residual(
                        url: itemURL,
                        tier: .tier2,
                        bytes: size,
                        selectedByDefault: false,
                        note: "Trùng tên ứng dụng (\(itemURL.lastPathComponent))"
                    ))
                }
            }
        }

        // 3. Tier 3: Vendor Matching
        let bundleParts = info.bundleID.split(separator: ".")
        var vendorCandidates: Set<String> = []
        if bundleParts.count >= 2 {
            vendorCandidates.insert(String(bundleParts[1]).lowercased())
        }
        for known in knownVendors where info.bundleID.lowercased().contains(known) {
            vendorCandidates.insert(known)
        }

        for subpath in ["Application Support", "Caches"] {
            let rootURL = libraryURL.appending(path: subpath)
            guard let contents = try? fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) else {
                continue
            }

            for itemURL in contents {
                let folderName = itemURL.lastPathComponent.lowercased()
                if vendorCandidates.contains(folderName) {
                    if residuals.contains(where: { $0.url == itemURL }) { continue }

                    // Check if other apps from this vendor are still installed
                    let otherVendorAppsExist = installedAppIDs.contains { otherID in
                        !info.ownedIDs.contains(otherID) && otherID.lowercased().contains(folderName)
                    }

                    guard case .allowed = CleanerPathGuard.check(itemURL, home: home) else {
                        continue
                    }

                    let size = AppBundleAnalyzer.calculateAllocatedSize(of: itemURL)
                    residuals.append(Residual(
                        url: itemURL,
                        tier: .tier3,
                        bytes: size,
                        selectedByDefault: false,
                        locked: otherVendorAppsExist,
                        note: otherVendorAppsExist
                            ? "Thư mục dùng chung của \(itemURL.lastPathComponent) (Còn ứng dụng khác đang dùng)"
                            : "Thư mục nhà phát triển \(itemURL.lastPathComponent)"
                    ))
                }
            }
        }

        return residuals
    }
}
