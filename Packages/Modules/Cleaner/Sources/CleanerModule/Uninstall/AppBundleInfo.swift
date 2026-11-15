import Foundation

/// Metadata and bundle identity of a macOS application package.
nonisolated public struct AppBundleInfo: Identifiable, Equatable, Sendable {
    public var id: String { bundleID }
    public let url: URL
    public let bundleID: String
    public let displayName: String
    public let version: String
    public let sizeBytes: Int64
    public let ownedIDs: Set<String>

    public init(
        url: URL,
        bundleID: String,
        displayName: String,
        version: String,
        sizeBytes: Int64,
        ownedIDs: Set<String> = []
    ) {
        self.url = url
        self.bundleID = bundleID
        self.displayName = displayName
        self.version = version
        self.sizeBytes = sizeBytes
        self.ownedIDs = ownedIDs.union([bundleID])
    }
}

/// Analyzes a `.app` bundle package to inspect bundle ID, nested helpers, and allocated disk size.
nonisolated public enum AppBundleAnalyzer {
    public enum AnalyzeError: Error, LocalizedError, Equatable {
        case notAnAppBundle
        case systemAppNotAllowed
        case appleAppNotAllowed
        case myNotchSelfNotAllowed
        case missingBundleID
        case cannotReadBundle

        public var errorDescription: String? {
            switch self {
            case .notAnAppBundle: return "Đường dẫn không phải là một gói ứng dụng macOS (.app)"
            case .systemAppNotAllowed: return "Không thể gỡ bỏ ứng dụng thuộc hệ điều hành macOS (/System)"
            case .appleAppNotAllowed: return "Không thể gỡ bỏ ứng dụng mặc định của Apple (com.apple.*)"
            case .myNotchSelfNotAllowed: return "Không thể tự gỡ bỏ MyNotch"
            case .missingBundleID: return "Gói ứng dụng không chứa CFBundleIdentifier hợp lệ"
            case .cannotReadBundle: return "Không thể đọc nội dung của gói ứng dụng"
            }
        }
    }

    /// Analyzes a target URL pointing to a macOS `.app` bundle.
    public static func analyze(url: URL) throws -> AppBundleInfo {
        guard url.pathExtension.lowercased() == "app" else {
            throw AnalyzeError.notAnAppBundle
        }

        let canonicalPath = url.resolvingSymlinksInPath().path
        if canonicalPath.hasPrefix("/System") {
            throw AnalyzeError.systemAppNotAllowed
        }

        let infoPlistURL = url.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String, !bundleID.isEmpty else {
            throw AnalyzeError.missingBundleID
        }

        if bundleID.lowercased().hasPrefix("com.apple.") {
            throw AnalyzeError.appleAppNotAllowed
        }

        if bundleID.lowercased().hasPrefix("io.lucasvu.mynotch") || canonicalPath.lowercased().contains("mynotch.app") {
            throw AnalyzeError.myNotchSelfNotAllowed
        }

        let displayName = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        let version = (plist["CFBundleShortVersionString"] as? String)
            ?? (plist["CFBundleVersion"] as? String)
            ?? "1.0"

        let sizeBytes = calculateAllocatedSize(of: url)
        let ownedIDs = scanNestedBundleIDs(in: url).union([bundleID])

        return AppBundleInfo(
            url: url,
            bundleID: bundleID,
            displayName: displayName,
            version: version,
            sizeBytes: sizeBytes,
            ownedIDs: ownedIDs
        )
    }

    /// Recursively calculates total disk size without traversing symbolic links.
    public static func calculateAllocatedSize(of targetURL: URL) -> Int64 {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: targetURL.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            if let resourceValues = try? targetURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]),
               let size = resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? resourceValues.fileSize, size > 0 {
                return Int64(size)
            }
            if let attrs = try? fileManager.attributesOfItem(atPath: targetURL.path),
               let size = attrs[.size] as? Int64 {
                return size
            }
            return 0
        }

        guard let enumerator = fileManager.enumerator(
            at: targetURL,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isSymbolicLinkKey]),
                  resourceValues.isSymbolicLink != true else {
                continue
            }
            let size = resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? resourceValues.fileSize ?? 0
            if size > 0 {
                total += Int64(size)
            } else if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
                      let fallback = attrs[.size] as? Int64 {
                total += fallback
            }
        }
        return total
    }

    /// Scans nested LoginItems, XPC services, and helpers for sub-bundle IDs.
    public static func scanNestedBundleIDs(in bundleURL: URL) -> Set<String> {
        var ids: Set<String> = []
        let searchDirectories = ["Contents/Library/LoginItems", "Contents/XPCServices", "Contents/Helpers"]
        let fileManager = FileManager.default

        for subDir in searchDirectories {
            let dirURL = bundleURL.appending(path: subDir)
            guard let items = try? fileManager.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) else { continue }
            for item in items where item.pathExtension.lowercased() == "app" || item.pathExtension.lowercased() == "xpc" {
                let subPlist = item.appending(path: "Contents/Info.plist")
                if let data = try? Data(contentsOf: subPlist),
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let subID = plist["CFBundleIdentifier"] as? String, !subID.isEmpty {
                    ids.insert(subID)
                }
            }
        }
        return ids
    }
}
