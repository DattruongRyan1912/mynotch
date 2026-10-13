import Foundation

/// One look at a path in the Downloads folder, taken after a file-system event.
nonisolated struct FileObservation: Equatable, Sendable {
    struct Flags: OptionSet, Sendable {
        let rawValue: Int
        static let created = Flags(rawValue: 1)
        static let renamed = Flags(rawValue: 2)
        /// The path is gone now; coalesced events can carry other flags too, so `read` normalizes this.
        static let removed = Flags(rawValue: 4)
        static let modified = Flags(rawValue: 8)
    }

    var path: String
    var flags: Flags
    var size: Int64
    /// Whether the file carries a quarantine or "where from" attribute, which browsers set on downloads.
    var hasOrigin: Bool
    var isDirectory: Bool
    /// Modification time. Quarantine and Spotlight changes leave it alone, so it tells a fresh download from an old file that was touched.
    var date: Date

    /// Stats the file; a path that no longer exists is reported as exactly `.removed`.
    static func read(_ url: URL, flags: Flags) -> FileObservation {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return FileObservation(path: url.path, flags: .removed, size: 0, hasOrigin: false, isDirectory: false, date: .distantPast)
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let isDirectory = attributes[.type] as? FileAttributeType == .typeDirectory
        let date = attributes[.modificationDate] as? Date ?? .distantPast
        return FileObservation(
            path: url.path, flags: flags.subtracting(.removed), size: size,
            hasOrigin: hasAttribute("com.apple.quarantine", at: url) || hasAttribute("com.apple.metadata:kMDItemWhereFroms", at: url),
            isDirectory: isDirectory, date: date)
    }

    private static func hasAttribute(_ name: String, at url: URL) -> Bool {
        getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }
}
