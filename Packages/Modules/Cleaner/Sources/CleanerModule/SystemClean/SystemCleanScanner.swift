import Darwin
import Foundation
import MyNotchCore

/// Scans developer artifacts and system junk within user home (NC-MYN-026, 029).
nonisolated public enum SystemCleanScanner {
    public struct ScanResult: Sendable {
        public let categories: [StorageCategory]
        public let plans: [String: DeletionPlan]

        public init(categories: [StorageCategory], plans: [String: DeletionPlan]) {
            self.categories = categories
            self.plans = plans
        }
    }

    /// Performs background measurement of system and developer cleaning targets.
    public static func scan(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        runningIDs: Set<String> = [],
        runningNames: Set<String> = []
    ) async -> ScanResult {
        await UtilityIO.run {
            var categories: [StorageCategory] = []
            var plans: [String: DeletionPlan] = [:]
            let fileManager = FileManager.default

            let lowerRunningNames = Set(runningNames.map { $0.lowercased() })

            for entry in CleanerCatalog.entries {
                var plannedItems: [PlannedItem] = []
                var entryNeedsFDA = false
                var totalBytes: Int64 = 0

                for relPath in entry.relativePaths {
                    let targetURL = home.appending(path: relPath)
                    let pathStr = targetURL.path

                    // Probe root existence and permission
                    let fd = open(pathStr, O_RDONLY | O_DIRECTORY)
                    if fd < 0 {
                        let err = errno
                        if err == EPERM || err == EACCES {
                            entryNeedsFDA = true
                            continue
                        } else if err == ENOENT {
                            continue
                        }
                    } else {
                        close(fd)
                    }

                    // Enumerate direct children of this location
                    guard let contents = try? fileManager.contentsOfDirectory(
                        at: targetURL,
                        includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isSymbolicLinkKey]
                    ) else {
                        continue
                    }

                    for childURL in contents {
                        let childName = childURL.lastPathComponent

                        // Specific exclusions for General User Caches (cleaner.system.usercaches)
                        if entry.id == "cleaner.system.usercaches" {
                            if CleanerCatalog.devCacheSubpaths.contains(childName) { continue }
                            if childName.lowercased().hasPrefix("com.apple.") { continue }
                            if childName.lowercased().contains("mynotch") { continue }
                            if runningIDs.contains(childName) || lowerRunningNames.contains(childName.lowercased()) {
                                continue
                            }
                        }

                        // General exclusions for System Logs
                        if entry.id == "cleaner.system.logs" {
                            if childName.lowercased().hasPrefix("com.apple.") { continue }
                            if childName.lowercased().contains("mynotch") { continue }
                        }

                        // Path guard check
                        guard case .allowed = CleanerPathGuard.check(childURL, home: home) else {
                            continue
                        }

                        let itemSize = AppBundleAnalyzer.calculateAllocatedSize(of: childURL)
                        if let planned = PlannedItem.capture(url: childURL, bytes: itemSize) {
                            plannedItems.append(planned)
                            totalBytes += itemSize
                        }
                    }
                }

                let canClean = totalBytes > 0
                let category = StorageCategory(
                    id: entry.id,
                    title: entry.title,
                    bytes: totalBytes,
                    keeps: nil,
                    canClean: canClean,
                    scope: entry.scope,
                    needsFullDiskAccess: entryNeedsFDA,
                    caution: entry.caution
                )

                categories.append(category)
                plans[entry.id] = DeletionPlan(items: plannedItems)
            }

            return ScanResult(categories: categories, plans: plans)
        }
    }
}
