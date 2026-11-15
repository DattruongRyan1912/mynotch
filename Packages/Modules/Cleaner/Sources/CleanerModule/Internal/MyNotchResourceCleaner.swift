import AppKit
import Darwin
import Foundation
import MyNotchCore

nonisolated public struct MyNotchAppCacheScan: Sendable, Equatable {
    public let appCacheBytes: Int64
    public let appLogBytes: Int64
    public var totalBytes: Int64 { appCacheBytes + appLogBytes }

    public init(appCacheBytes: Int64 = 0, appLogBytes: Int64 = 0) {
        self.appCacheBytes = appCacheBytes
        self.appLogBytes = appLogBytes
    }
}

nonisolated public struct MemoryReliefReport: Sendable, Equatable {
    public let reclaimedZoneBytes: Int
    public let footprintBeforeBytes: UInt64
    public let footprintAfterBytes: UInt64

    public init(
        reclaimedZoneBytes: Int,
        footprintBeforeBytes: UInt64,
        footprintAfterBytes: UInt64
    ) {
        self.reclaimedZoneBytes = reclaimedZoneBytes
        self.footprintBeforeBytes = footprintBeforeBytes
        self.footprintAfterBytes = footprintAfterBytes
    }
}

nonisolated public enum MyNotchResourceCleaner {
    nonisolated private static let skippedCacheSubdirectories: Set<String> = ["Modules"]

    // MARK: - Scanning

    nonisolated public static func scanAppCachesAndLogs(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundleID: String = Bundle.main.bundleIdentifier ?? "io.lucasvu.mynotch"
    ) async -> MyNotchAppCacheScan {
        await UtilityIO.run {
            let cachesDir = home.appending(path: "Library/Caches/\(bundleID)")
            let logsDir = home.appending(path: "Library/Logs/MyNotch")
            let bundleLogsDir = home.appending(path: "Library/Logs/\(bundleID)")

            let cacheBytes = scanFolder(cachesDir, skippingSubdirectories: skippedCacheSubdirectories)
            var logBytes = scanFolder(logsDir)
            if bundleLogsDir.standardizedFileURL != logsDir.standardizedFileURL {
                logBytes += scanFolder(bundleLogsDir)
            }

            return MyNotchAppCacheScan(appCacheBytes: cacheBytes, appLogBytes: logBytes)
        }
    }

    // MARK: - Cleaning

    nonisolated public static func cleanAppCachesAndLogs(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundleID: String = Bundle.main.bundleIdentifier ?? "io.lucasvu.mynotch"
    ) async -> Int64 {
        await UtilityIO.run {
            let cachesDir = home.appending(path: "Library/Caches/\(bundleID)")
            let logsDir = home.appending(path: "Library/Logs/MyNotch")
            let bundleLogsDir = home.appending(path: "Library/Logs/\(bundleID)")

            var freed: Int64 = 0
            freed += cleanFolder(cachesDir, skippingSubdirectories: skippedCacheSubdirectories)
            freed += cleanFolder(logsDir)
            if bundleLogsDir.standardizedFileURL != logsDir.standardizedFileURL {
                freed += cleanFolder(bundleLogsDir)
            }

            return freed
        }
    }

    // MARK: - Default Safe Selection

    nonisolated public static func defaultSafeSelectedIDs(
        categories: [StorageCategory],
        runningBundleIDs: Set<String> = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    ) -> Set<String> {
        let isXcodeRunning = runningBundleIDs.contains("com.apple.dt.Xcode")
        var selected = Set<String>()
        for category in categories where category.canClean && category.bytes > 0 {
            if category.id == "cleaner.system.trash" {
                continue
            }
            if category.id == "cleaner.dev.deriveddata" && isXcodeRunning {
                continue
            }
            selected.insert(category.id)
        }
        return selected
    }

    // MARK: - Process Memory Relief

    nonisolated public static func defaultMemoryFootprint() -> UInt64 {
        var rusage = rusage_info_current()
        let result = withUnsafeMutablePointer(to: &rusage) { ptr in
            ptr.withMemoryRebound(to: (rusage_info_t?).self, capacity: 1) { rusagePtr in
                proc_pid_rusage(getpid(), RUSAGE_INFO_CURRENT, rusagePtr)
            }
        }
        if result == 0 {
            return rusage.ri_phys_footprint
        }
        return 0
    }

    nonisolated public static func relieveProcessMemory(
        relieve: (@Sendable () -> Int)? = nil,
        footprintProvider: (@Sendable () -> UInt64)? = nil
    ) async -> MemoryReliefReport {
        let readFootprint = footprintProvider ?? { defaultMemoryFootprint() }
        let footprintBefore = readFootprint()

        let runRelief = relieve ?? { malloc_zone_pressure_relief(nil, 0) }

        // Run relief off main thread with utility I/O policy
        let reclaimed = await UtilityIO.run {
            runRelief()
        }

        let footprintAfter = readFootprint()
        return MemoryReliefReport(
            reclaimedZoneBytes: reclaimed,
            footprintBeforeBytes: footprintBefore,
            footprintAfterBytes: footprintAfter
        )
    }

    // MARK: - Folder Traversal Helpers

    nonisolated private static func isSymlink(_ url: URL) -> Bool {
        var statBuf = stat()
        guard lstat(url.path(percentEncoded: false), &statBuf) == 0 else { return false }
        return (statBuf.st_mode & S_IFMT) == S_IFLNK
    }

    nonisolated private static func scanFolder(_ rootURL: URL, skippingSubdirectories: Set<String> = []) -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: rootURL.path(percentEncoded: false)), !isSymlink(rootURL) else {
            return 0
        }

        var totalBytes: Int64 = 0
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else {
            return 0
        }

        while let fileURL = enumerator.nextObject() as? URL {
            if isSymlink(fileURL) {
                enumerator.skipDescendants()
                continue
            }
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey])
            if values?.isDirectory == true {
                if skippingSubdirectories.contains(fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
            }
            if values?.isRegularFile == true {
                totalBytes += Int64(values?.fileSize ?? 0)
            }
        }

        return totalBytes
    }

    nonisolated private static func cleanFolder(_ rootURL: URL, skippingSubdirectories: Set<String> = []) -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: rootURL.path(percentEncoded: false)), !isSymlink(rootURL) else {
            return 0
        }

        var freed: Int64 = 0
        let contents = (try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        )) ?? []

        let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        let canonicalRootPrefix = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"

        for itemURL in contents {
            if skippingSubdirectories.contains(itemURL.lastPathComponent) {
                continue
            }
            if isSymlink(itemURL) {
                try? fm.removeItem(at: itemURL)
                continue
            }
            let canonicalItem = itemURL.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
            guard canonicalItem.hasPrefix(canonicalRootPrefix) else {
                continue
            }
            let values = try? itemURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isDirectoryKey])
            if values?.isDirectory == true {
                let size = scanFolder(itemURL)
                if (try? fm.removeItem(at: itemURL)) != nil {
                    freed += size
                }
            } else if values?.isRegularFile == true {
                let size = Int64(values?.fileSize ?? 0)
                if (try? fm.removeItem(at: itemURL)) != nil {
                    freed += size
                }
            }
        }

        return freed
    }
}
