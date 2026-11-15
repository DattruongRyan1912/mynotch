import Darwin
import Foundation

/// Item kind discovered during filesystem scan.
nonisolated public enum ItemKind: String, Codable, Sendable {
    case file
    case directory
    case symlink
}

/// A specific filesystem node scheduled for immutable deletion (NC-MYN-029).
nonisolated public struct PlannedItem: Identifiable, Equatable, Sendable {
    public var id: String { path }
    public let path: String
    public let url: URL
    public let kind: ItemKind
    public let dev: dev_t
    public let ino: ino_t
    public let mtimeNs: Int64
    public let bytes: Int64
    public let canonicalParent: String
    public let ownerBundleID: String?

    public init(
        url: URL,
        kind: ItemKind,
        dev: dev_t,
        ino: ino_t,
        mtimeNs: Int64,
        bytes: Int64,
        canonicalParent: String,
        ownerBundleID: String? = nil
    ) {
        self.path = url.path
        self.url = url
        self.kind = kind
        self.dev = dev
        self.ino = ino
        self.mtimeNs = mtimeNs
        self.bytes = bytes
        self.canonicalParent = canonicalParent
        self.ownerBundleID = ownerBundleID
    }

    /// Captures the filesystem attributes of a target URL into a PlannedItem using lstat (no symlink following).
    public static func capture(url: URL, bytes: Int64, ownerBundleID: String? = nil) -> PlannedItem? {
        var statBuf = stat()
        let ret = lstat(url.path, &statBuf)
        guard ret == 0 else { return nil }

        let mode = statBuf.st_mode
        let kind: ItemKind
        if (mode & S_IFMT) == S_IFLNK {
            kind = .symlink
        } else if (mode & S_IFMT) == S_IFDIR {
            kind = .directory
        } else {
            kind = .file
        }

        let canonicalParent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardized.path
        let mtimeNs = Int64(statBuf.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(statBuf.st_mtimespec.tv_nsec)

        return PlannedItem(
            url: url,
            kind: kind,
            dev: statBuf.st_dev,
            ino: statBuf.st_ino,
            mtimeNs: mtimeNs,
            bytes: bytes,
            canonicalParent: canonicalParent,
            ownerBundleID: ownerBundleID
        )
    }
}

/// An immutable plan of deletion items produced by scan phase before execution (NC-MYN-029).
nonisolated public struct DeletionPlan: Equatable, Sendable {
    public let items: [PlannedItem]

    public init(items: [PlannedItem]) {
        self.items = items
    }

    public var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.bytes }
    }
}

/// Mode of item removal.
nonisolated public enum DeletionMode: Sendable {
    case trash
    case unlink
}

/// Execution outcome report of a DeletionPlan.
nonisolated public struct ExecutionReport: Sendable {
    public var removed: [URL] = []
    public var resultingTrashURLs: [URL] = []
    public var freedBytes: Int64 = 0
    public var skippedChanged: Int = 0
    public var skippedRunning: Int = 0
    public var failed: [(url: URL, error: String)] = []

    public init() {}
}

/// Safely executes an immutable DeletionPlan with strict TOCTOU revalidation.
nonisolated public enum DeletionExecutor {
    public typealias Trasher = (URL) throws -> URL?

    public static func execute(
        plan: DeletionPlan,
        mode: DeletionMode,
        runningIDs: Set<String> = [],
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        trasher: Trasher? = nil
    ) -> ExecutionReport {
        var report = ExecutionReport()
        let fileManager = FileManager.default

        for item in plan.items {
            // Guard: Check if owning app started running
            if let owner = item.ownerBundleID, runningIDs.contains(owner) {
                report.skippedRunning += 1
                continue
            }

            // Guard: Check path safety again
            guard case .allowed = CleanerPathGuard.check(item.url, home: home) else {
                report.failed.append((item.url, "PathGuard rejected path"))
                continue
            }

            // TOCTOU Revalidation: lstat target
            var statBuf = stat()
            guard lstat(item.url.path, &statBuf) == 0 else {
                report.skippedChanged += 1
                continue
            }

            // Revalidate device, inode, and kind
            guard statBuf.st_dev == item.dev, statBuf.st_ino == item.ino else {
                report.skippedChanged += 1
                continue
            }

            let modeBits = statBuf.st_mode
            let currentKind: ItemKind
            if (modeBits & S_IFMT) == S_IFLNK {
                currentKind = .symlink
            } else if (modeBits & S_IFMT) == S_IFDIR {
                currentKind = .directory
            } else {
                currentKind = .file
            }

            guard currentKind == item.kind else {
                report.skippedChanged += 1
                continue
            }

            // Revalidate parent directory resolution
            let currentParent = item.url.deletingLastPathComponent().resolvingSymlinksInPath().standardized.path
            guard currentParent == item.canonicalParent else {
                report.skippedChanged += 1
                continue
            }

            // Execute deletion
            do {
                switch mode {
                case .trash:
                    if let customTrasher = trasher {
                        if let trashedURL = try customTrasher(item.url) {
                            report.resultingTrashURLs.append(trashedURL)
                        }
                    } else {
                        var resultingURL: NSURL?
                        try fileManager.trashItem(at: item.url, resultingItemURL: &resultingURL)
                        if let res = resultingURL as URL? {
                            report.resultingTrashURLs.append(res)
                        }
                    }
                case .unlink:
                    try fileManager.removeItem(at: item.url)
                }

                report.removed.append(item.url)
                report.freedBytes += item.bytes
            } catch {
                report.failed.append((item.url, error.localizedDescription))
            }
        }

        return report
    }
}
